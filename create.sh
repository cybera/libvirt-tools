#!/bin/bash

name=""
os=""
cpus="2"
ram="512"
disk="20G"
bridge=""
ip=""
ip6=""
gateway=""
ip6_gateway=""
dns=""

function help {
  echo "Usage:"
  echo "  create.sh --name --os [ --cpus --ram --disk --bridge --ip --gateway --ip6 --ip6_gateway --dns]"
  echo ""
  echo " --name: Name of the VM. Required."
  echo " --os: OS of the VM (.img file without .img). Required."
  echo " --cpus: No. of CPUs. Default of 2."
  echo " --ram: Amount of RAM. Default of 512."
  echo " --disk: Size of disk. Default of 20G."
  echo " --bridge: Name of bridge. Uses NAT and DHCP if omitted."
  echo ""
  echo "Bridge options:"
  echo " --ip: Static IP address."
  echo " --gateway: Gateway IP."
  echo " --ip6: Static IPv6 address."
  echo " --ip6_gateway: IPv6 gateway."
  echo " --dns: DNS server."
  echo ""
  echo "Check /var/lib/libvirt/templates for available images."
  echo "The os is the basename of the template."
  exit 1
}

while :; do
  case $1 in
    --name)
      name="$2"
      shift 2
      continue
      ;;
    --name=?*)
      name=${1#*=}
      ;;

    --os)
      os="$2"
      shift 2
      continue
      ;;
    --os=?*)
      os=${1#*=}
      ;;

    --cpus)
      cpus="$2"
      shift 2
      continue
      ;;
    --cpus=?*)
      cpus=${1#*=}
      ;;

    --ram)
      ram="$2"
      shift 2
      continue
      ;;
    --ram=?*)
      ram=${1#*=}
      ;;

    --disk)
      disk="$2"
      shift 2
      continue
      ;;
    --disk=?*)
      disk=${1#*=}
      ;;

    --bridge)
      bridge="$2"
      shift 2
      continue
      ;;
    --bridge=?*)
      bridge=${1#*=}
      ;;

    --ip)
      ip="$2"
      shift 2
      continue
      ;;
    --ip=?*)
      ip=${1#*=}
      ;;

    --gateway)
      gateway="$2"
      shift 2
      continue
      ;;
    --gateway=?*)
      gateway=${1#*=}
      ;;

    --ip6)
      ip6="$2"
      shift 2
      continue
      ;;
    --ip6=?*)
      ip6=${1#*=}
      ;;

    --ip6_gateway)
      ip6_gateway="$2"
      shift 2
      continue
      ;;
    --ip6_gateway=?*)
      ip6_gateway=${1#*=}
      ;;

    --dns)
      dns="$2"
      shift 2
      continue
      ;;
    --dns=?*)
      dns=${1#*=}
      ;;

    --help)
      help
      exit 1
      ;;
    *)
      break
  esac
  shift
done

if [[ -z $name || -z $os ]]; then
  help
  exit 1
fi

space=" |'"
if [[ $name =~ $space ]]; then
  echo "$name contains a space. Please don't do this."
  exit 1
fi

if [[ ! -f "/root/.ssh/id_rsa" ]]; then
  echo "Root has no SSH key. Please generate one first."
  exit 1
fi

if [[ ! -f "/var/lib/libvirt/templates/${os}.img" ]]; then
  echo "OS $os does not exist."
  exit 1
fi

if [[ -n $bridge ]]; then
  ip link show dev $bridge >/dev/null 2>&1
  if [[ $? != 0 ]]; then
    echo "Bridge $bridge does not exist."
    exit 1
  fi
fi

os_type="linux"
if [[ $os =~ "windows" ]]; then
  os_type="windows"
fi

if [[ -f "/var/lib/libvirt/images/${name}.img" ]]; then
  echo "VM already exists."
  exit 1
fi

extra_config_drive_options=""
user_data=""

iface="eth0"
if [[ $os =~ "1604" ]]; then
  iface="ens3"
fi

network_config="--network model=virtio,network=default"
if [[ -n $bridge ]]; then
  network_config="--network model=virtio,bridge=$bridge"

  if [[ -n $ip && -n $gateway && -n $dns && -n $ip6 && -n $ip6_gateway ]]; then
    if [[ $os =~ "ubuntu" ]]; then
      user_data=$(mktemp)
      cat >$user_data <<EOF
#!/bin/bash
cat >/etc/network/interfaces <<EOFF
auto lo
iface lo inet loopback

auto $iface
iface $iface inet static
    address $ip
    netmask 255.255.255.0
    gateway $gateway
    dns-nameservers $dns

iface $iface inet6 static
    address $ip6
    gateway $ip6_gateway
    netmask 64
EOFF
ifdown $iface
sleep 2
ifup $iface
EOF
      extra_config_drive_options="--user-data $user_data"
    fi
  fi
fi

which create-config-drive >/dev/null
if [[ $? != 0 ]]; then
  wget -O /usr/local/bin/create-config-drive https://raw.githubusercontent.com/larsks/virt-utils/master/create-config-drive
  chmod +x /usr/local/bin/create-config-drive
fi

echo " ===> Creating cloud init ISO"
create-config-drive -k /root/.ssh/id_rsa.pub --hostname $name $extra_config_drive_options "/var/lib/libvirt/images/${name}_cloudinit.iso"

if [[ -n $user_data ]]; then
  rm $user_data
fi

echo " ===> Copying template to VM image"
cp -v /var/lib/libvirt/templates/${os}.img /var/lib/libvirt/images/${name}.img

echo " ===> Resizing image to $disk"
pushd /var/lib/libvirt/images
  qemu-img resize "${name}.img" +${disk}
popd

echo " ===> Creating VM"
virt-install -n $name -r $ram --vcpus $cpus --disk path=/var/lib/libvirt/images/${name}.img,device=disk --disk path=/var/lib/libvirt/images/${name}_cloudinit.iso,device=cdrom --import --os-type $os_type --graphics none --serial pty --console pty --graphics vnc $network_config --noautoconsole
