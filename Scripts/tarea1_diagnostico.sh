echo "Hostname"
hostname

echo ""
echo "IP"
ip -4 addr |grep inet|grep -v 127.0.0.1| awk '{print$2}'
echo ""
echo "Espacio en el disco"
df -h /