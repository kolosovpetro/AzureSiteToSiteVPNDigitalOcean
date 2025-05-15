sudo apt update
sudo apt install strongswan

sudo vim /etc/ipsec.conf
sudo vim /etc/ipsec.secrets
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

sudo ipsec restart
ipsec status
