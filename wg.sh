#!/bin/bash
# www.radaco.net By E.Rahmatian		email:e.rahmatian@gmail.com



BLUE='\033034'
NC='\033[0m'
INFO="${BLUE}[i]${NC}"

function installWireGuard() {

    #? Check root user
    if [ "${EUID}" -ne 0 ]; then
		echo "You need to run this script as root"
		exit 13
	fi

    #? Check OS version
    if [[ -e /etc/debian_version ]]; then
        # shellcheck source=/dev/null
		source /etc/os-release
		OS="${ID}" # debian or ubuntu
		if [[ ${ID} == "debian" || ${ID} == "raspbian" ]]; then
			if [[ ${VERSION_ID} -lt 10 ]]; then
				echo "Your version of Debian (${VERSION_ID}) is not supported. Please use Debian 10 Buster or later"
				exit 95
			fi
			OS=debian #* overwrite if raspbian
		fi
	elif [[ -e /etc/fedora-release ]]; then
        # shellcheck source=/dev/null
		source /etc/os-release
		OS="${ID}"
	elif [[ -e /etc/centos-release ]]; then
        # shellcheck source=/dev/null
		source /etc/os-release
		OS=centos
	elif [[ -e /etc/oracle-release ]]; then
        # shellcheck source=/dev/null
		source /etc/os-release
		OS=oracle
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	else
		echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Oracle or Arch Linux system"
		exit 95
	fi

	#? Install WireGuard tools and module
	if [[ ${OS} == 'ubuntu' ]] || [[ ${OS} == 'debian' && ${VERSION_ID} -gt 10 ]]; then
		apt-get update
		apt-get install -y wireguard qrencode sshpass
	elif [[ ${OS} == 'debian' ]]; then
		if ! grep -rqs "^deb .* buster-backports" /etc/apt/; then
			echo "deb http://deb.debian.org/debian buster-backports main" >/etc/apt/sources.list.d/backports.list
			apt-get update
		fi
		apt update
		apt-get install -y qrencode
		apt-get install -y sshpass
		apt-get install -y -t buster-backports wireguard
	elif [[ ${OS} == 'fedora' ]]; then
		if [[ ${VERSION_ID} -lt 32 ]]; then
			dnf install -y dnf-plugins-core
			dnf copr enable -y jdoss/wireguard
			dnf install -y wireguard-dkms
		fi
		dnf install -y wireguard-tools qrencode sshpass
	elif [[ ${OS} == 'centos' ]]; then
		yum -y install epel-release elrepo-release
		if [[ ${VERSION_ID} -eq 7 ]]; then
			yum -y install yum-plugin-elrepo sshpass
		fi
		yum -y install kmod-wireguard wireguard-tools qrencode sshpass
	elif [[ ${OS} == 'oracle' ]]; then
		dnf install -y oraclelinux-developer-release-el8
		dnf config-manager --disable -y ol8_developer
		dnf config-manager --enable -y ol8_developer_UEKR6
		dnf config-manager --save -y --setopt=ol8_developer_UEKR6.includepkgs='wireguard-tools*'
		dnf install -y wireguard-tools qrencode sshpass
	elif [[ ${OS} == 'arch' ]]; then
		pacman -Sq --needed --noconfirm wireguard-tools qrencode sshpass
	fi

}

function installCheck() {
	if ! command -v wg &> /dev/null
	then
	    echo "You must have \"wireguard-tools\" and \"qrencode\" installed."
    	read -n1 -r -p "Press any key to continue and install needed packages..."
		installWireGuard
	fi

        if ! sshpass -v wg &> /dev/null
        then
            #echo " Installing sshpass"
        #read -n1 -r -p "Press any key to continue and install needed packages..."
                yum install sshpass -y
        fi

}
######### ssh check ##########

#####################  ROUTER SETUP ##############
router-setup() {
echo "Enter the Remote UserName"
read rmtuname
echo "Enter the Remote Password"
read -s rmtpasswrd

echo "Enter Mikrotik ip"
read  server

echo This file is Mikrotik Router Credentials
echo username=$rmtuname >> wireguard/router.conf
echo password=$rmtpasswrd >> wireguard/router.conf
echo server=$server >> wireguard/router.conf
source wireguard/router.conf

#clear

################## ROUTER SETUP FILE FINISHED ###########
################# TESTING THE CONNECTION #############
echo Checking the connection to router

shpass -p $password ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no $username@$server "int pr"
#sshpass -p $password ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $username@$server "int pr"


    let ret=$?

    if [ $ret -eq 5 ]; then
        echo $server$i "Refused!"  $ret
    elif [ $ret -eq 0 ] ; then
	 clear
        echo $server$i "Connection to router was OK, Status Code " $ret
    else
        echo $server$i "Unknown return code!" $ret
    fi  
}

############### TESING CONNECTION FINISHED ######################


















function serverName() {
	until [[ ${SERVER_WG_NIC} =~ ^[a-zA-Z0-9_]+$ && ${#SERVER_WG_NIC} -lt 16 ]]; do
            read -rp "WireGuard interface name (server name): " -e -i wg0 SERVER_WG_NIC
    done
}

function installQuestions() {
	echo "Welcome to WireGuard-MikroTik configurator!"
	echo "The git repository is available at: https://github.com/radaco-net/wireguard-mikrotik"
	
	# Detect public IPv4 or IPv6 address and pre-fill for the user
    SERVER_PUB_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
    if [[ -z ${SERVER_PUB_IP} ]]; then
            # Detect public IPv6 address
            SERVER_PUB_IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    fi
    read -rp "IPv4 or IPv6 public address: " -e -i "${SERVER_PUB_IP}" SERVER_PUB_IP

    until [[ ${SERVER_WG_IPV4} =~ ^([0-9]{1,3}\.){3} ]]; do
        read -rp "Server's WireGuard IPv4: " -e -i 10."$(shuf -i 0-250 -n 1)"."$(shuf -i 0-250 -n 1)".1 SERVER_WG_IPV4
    done

    until [[ ${SERVER_WG_IPV6} =~ ^([a-f0-9]{1,4}:){3,4}: ]]; do
        read -rp "Server's WireGuard IPv6: " -e -i fd42:"$(shuf -i 10-90 -n 1)":"$(shuf -i 10-90 -n 1)"::1 SERVER_WG_IPV6
    done

    # Generate random number within private ports range
    RANDOM_PORT=$(shuf -i49152-65535 -n1)
    until [[ ${SERVER_PORT} =~ ^[0-9]+$ ]] && [ "${SERVER_PORT}" -ge 1 ] && [ "${SERVER_PORT}" -le 65535 ]; do
        read -rp "Server's WireGuard port [1-65535]: " -e -i "${RANDOM_PORT}" SERVER_PORT
    done

    # Adguard DNS by default
    until [[ ${CLIENT_DNS_1} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
        read -rp "First DNS resolver to use for the clients: " -e -i 8.8.8.8 CLIENT_DNS_1
    done
    until [[ ${CLIENT_DNS_2} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
        read -rp "Second DNS resolver to use for the clients (optional): " -e -i 1.1.1.1 CLIENT_DNS_2
        if [[ ${CLIENT_DNS_2} == "" ]]; then
            CLIENT_DNS_2="${CLIENT_DNS_1}"
        fi
    done

    echo ""
    echo "Okay, that was all I needed. We are ready to setup your WireGuard server now."
    echo "You will be able to generate a client at the end of the installation."
    read -n1 -r -p "Press any key to continue..."

}

function newInterface() {
	# Run setup questions first
	installQuestions

	# Make sure the directory exists (this does not seem the be the case on fedora)
	mkdir -p "$(pwd)"/wireguard/"${SERVER_WG_NIC}"/mikrotik >/dev/null 2>&1

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

	# Save WireGuard settings #SERVER_PUB_NIC=${SERVER_PUB_NIC}
	echo "SERVER_PUB_IP=${SERVER_PUB_IP}

SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}" > "$(pwd)/wireguard/${SERVER_WG_NIC}/params"

    # Save WireGuard settings to the MikroTik
    echo "# WireGuard interface configure
/interface wireguard
add listen-port=${SERVER_PORT} mtu=1420 name=${SERVER_WG_NIC} private-key=\\
    \"${SERVER_PRIV_KEY}\"
/ip firewall filter
add action=accept chain=input comment=wg-${SERVER_WG_NIC} dst-port=${SERVER_PORT} protocol=udp
/ip firewall filter move [/ip firewall filter find comment=wg-${SERVER_WG_NIC}] 1
/ip address
add address=${SERVER_WG_IPV4}/24 comment=wg-${SERVER_WG_NIC} interface=${SERVER_WG_NIC}
    " > "$(pwd)/wireguard/${SERVER_WG_NIC}/mikrotik/${SERVER_WG_NIC}.rsc"


	# Add server interface
	echo "[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" > "$(pwd)/wireguard/${SERVER_WG_NIC}/${SERVER_WG_NIC}.conf"

	newClient
	echo -e "${INFO} MikroTik interface config available in $(pwd)/wireguard/${SERVER_WG_NIC}/mikrotik/${SERVER_WG_NIC}.rsc"
	echo -e "${INFO} If you want to add more clients, you simply need to run this script another time!"

}

function newClient() {
	ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

	echo ""
	echo "Name for the client."
	echo "The name must consist of alphanumeric character. It may also include an underscore or a dash and can't exceed 15 chars."

	until [[ ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ && ${CLIENT_EXISTS} == '0' && ${#CLIENT_NAME} -lt 16 ]]; do
		read -rp "Client name: " -e CLIENT_NAME
		CLIENT_EXISTS=$(grep -c -E "^### Client ${CLIENT_NAME}\$" "$(pwd)/wireguard/${SERVER_WG_NIC}/${SERVER_WG_NIC}.conf")

		if [[ ${CLIENT_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified name was already created, please choose another name."
			echo ""
		fi
	done

	for DOT_IP in {2..254}; do
		DOT_EXISTS=$(grep -c "${SERVER_WG_IPV4::-1}${DOT_IP}" "$(pwd)/wireguard/${SERVER_WG_NIC}/${SERVER_WG_NIC}.conf")
		if [[ ${DOT_EXISTS} == '0' ]]; then
			break
		fi
	done

	if [[ ${DOT_EXISTS} == '1' ]]; then
		echo ""
		echo "The subnet configured supports only 253 clients."
		exit 99
	fi

	BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
	until [[ ${IPV4_EXISTS} == '0' ]]; do
		read -rp "Client's WireGuard IPv4: ${BASE_IP}." -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV4="${BASE_IP}.${DOT_IP}"
		IPV4_EXISTS=$(grep -c "$CLIENT_WG_IPV4/24" "$(pwd)/wireguard/${SERVER_WG_NIC}/${SERVER_WG_NIC}.conf")

		if [[ ${IPV4_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified IPv4 was already created, please choose another IPv4."
			echo ""
		fi
	done

	BASE_IP=$(echo "$SERVER_WG_IPV6" | awk -F '::' '{ print $1 }')
	until [[ ${IPV6_EXISTS} == '0' ]]; do
		read -rp "Client's WireGuard IPv6: ${BASE_IP}::" -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV6="${BASE_IP}::${DOT_IP}"
		IPV6_EXISTS=$(grep -c "${CLIENT_WG_IPV6}/64" "$(pwd)/wireguard/${SERVER_WG_NIC}/${SERVER_WG_NIC}.conf")

		if [[ ${IPV6_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified IPv6 was already created, please choose another IPv6."
			echo ""
		fi
	done

	# Generate key pair for the client
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)

    mkdir -p "$(pwd)/wireguard/${SERVER_WG_NIC}/client/${CLIENT_NAME}" >/dev/null 2>&1
	HOME_DIR="$(pwd)/wireguard/${SERVER_WG_NIC}/client/${CLIENT_NAME}"

	# Create client file and add the server as a peer
	echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0,::/0" >>"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

    # Add the client as a peer to the MikroTik (to client folder)
    echo "/interface wireguard peers
add allowed-address=${CLIENT_WG_IPV4}/32 comment= \\
    ${CLIENT_NAME} interface=${SERVER_WG_NIC} \\
    preshared-key=\"${CLIENT_PRE_SHARED_KEY}\" public-key=\\
    \"${CLIENT_PUB_KEY}\"
    " >"${HOME_DIR}/mikrotik-peer-${SERVER_WG_NIC}-client-${CLIENT_NAME}.rsc"

    # Add the client as a peer to the MikroTik
    echo "/interface wireguard peers
add allowed-address=${CLIENT_WG_IPV4}/32 comment= \\
    ${SERVER_WG_NIC}-client-${CLIENT_NAME} interface=${SERVER_WG_NIC} \\
    preshared-key=\"${CLIENT_PRE_SHARED_KEY}\" public-key=\\
    \"${CLIENT_PUB_KEY}\"
    " >> "$(pwd)/wireguard/${SERVER_WG_NIC}/mikrotik/${SERVER_WG_NIC}.rsc"

	# Add the client as a peer to the server
	echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128" >>"$(pwd)/wireguard/${SERVER_WG_NIC}/${SERVER_WG_NIC}.conf"

	clear 
	echo -e "\nHere is your client config file as a QR Code:"
	echo ""
	qrencode -t ansiutf8 -l L <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
    qrencode -l L -s 6 -d 225 -o "${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.png" <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

#	echo -e "${INFO} Config available in ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
    #echo -e "${INFO} QR is also available in ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.png"
#	echo -e "${INFO} MikroTik peer config available in ${HOME_DIR}/mikrotik-peer-${SERVER_WG_NIC}-client-${CLIENT_NAME}.rsc"
	
mikconfigpath=${HOME_DIR}/mikrotik-peer-${SERVER_WG_NIC}-client-${CLIENT_NAME}.rsc;
mikconfig=`cat $mikconfigpath`


### checking router config if available
if ! [[ -e $(pwd)/wireguard/router.conf ]]; then
        # shellcheck source=/dev/null
        #source "$(pwd)/wireguard/router.conf"
        echo Mikrotik SSH config file is not found;
	read -p " Setup Router Again? (y/n) " answer
	case ${answer:0:1} in
    y|Y )
        echo Yes
        router-setup
#       clear
    ;;
    * )
       clear
    ;;
	esac
else 

source "$(pwd)/wireguard/router.conf"



sshpass -p $password ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no $username@$server $mikconfig


	fi


}



function manageMenu() {
	echo "Welcome to WireGuard-MikroTik configurator!"
	echo "The git repository is available at: https://github.com/IgorKha/wireguard-mikrotik"
	echo ""
	echo "It looks like this WireGuard interface is already."
	echo ""
	echo "What do you want to do?"
	echo "   1) Add a new client"
	echo "   2) Re-Config SSH Connection to Mikrotik "
	echo "   3) Show Public Key of server"
	echo "   4) Exit"
	until [[ ${MENU_OPTION} =~ ^[1-4]$ ]]; do
		read -rp "Select an option [1-2]: " MENU_OPTION
	done
	case "${MENU_OPTION}" in
	1)
		newClient
		;;

	2)	router-setup
		#exit 0
		;;

        3)
                clear
		echo -e "\e[1;31m  Warning!!! \e[0m"
		echo "You can change the public and private key from this file"
		echo $(pwd)/wireguard/${SERVER_WG_NIC}/params
		echo ""
		echo Public Key for mikrotik Server, Make sure your interface has the following Public Key
		echo ${SERVER_PUB_KEY}
                ;;

	4)
                exit 0
                ;;


	esac
}

#? Check for root, OS, WireGuard
installCheck

#? Check server exist
serverName

#? Check if WireGuard is already installed and load params
if [[ -e $(pwd)/wireguard/${SERVER_WG_NIC}/params ]]; then
	# shellcheck source=/dev/null
	source "$(pwd)/wireguard/${SERVER_WG_NIC}/params"
	manageMenu
else
	newInterface
fi
