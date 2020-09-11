#!/bin/bash
#AUTOMAAÇÃO de deploy de um site
##############################
# Função de checar os itens do site
############################
function check_item(){
  if [[ $1 = *$2* ]]
  then
    color "green" "Item $2 is present on the web page"
  else
    color "red" "Item $2 is not present on the web page"
  fi
}

############################################
# Função de testar serviços, quando ativo imprime em verde e quando não imprime em vermelho
###########################################
function test_service(){
	is_active=$(systemctl is-active $1)
	is_enabled=$(systemctl is-enabled $1)	
	if  [ "$is_active" = "active" ] && [ "$is_enabled" = "enabled" ] 
	then
	#if [ $is_anabeled = "enabled"]
	color green "$1 esta ativo e habilitado"
	else
	color red "$1 nao esta ativo ou nao esta habilitado"
	exit 1
	fi
}

############################################
# Função de aplicação de cores, no caso, verde, vermelho ou sem cor
###########################################
function color(){
NC='\033[0m' # No Color
case $1 in
	"green") COLOR='\033[0;32m' ;;
	"red") COLOR='\033[0;31m' ;;
	"*") COLOR='i033[0m' ;;
esac

echo -e "${COLOR} $2 ${NC} "

}

###################################################
# Função que se as portas do firewall estão devidamente configuradas
###################################################
function port_check(){
firewall_ports=$(sudo firewall-cmd --list-all --zone=public | grep ports)
if [[ $firewall_ports == *$1* ]]
	then
		color green " FirewallD está configurado na porta $1"
	else
		color red " FirewallD não foi configurado na porta $1"
	exit 1
fi

}

# Começando o scrtpt de deploy
echo "---------------- Setup Database Server ------------------"

# Install and configure firewalld
color "green" "Installing FirewallD.. "
sudo yum install -y firewalld
sudo service firewalld start
sudo systemctl enable firewalld
# Checando de o firewalld está ativo e habilitado
test_service firewalld


# Instalando e configurando Maria-DB
color "green" "Installing MariaDB Server.."
sudo yum install -y mariadb-server
# Ativando e habilitando mariadb-server
sudo service mariadb start
sudo systemctl enable mariadb
# Checando se o serviço está ativo e habilitado
test_service mariadb.service

# Configurando as regras no firewalld para o funcionamento do mariadb-sevrer
color green "configurando as regras firewalld para o banco de dados"
sudo firewall-cmd --permanent --zone=internal --add-port=3306/tcp
# Carregando a nova configuração do firewall
sudo firewall-cmd --reload
# Função que verifique se as portas do firewall estão devidamente configuradas
port_check 3306

# Configurando banco de dados 
color green "Configurando banco de dados"
cat > setup-db.sql <<-EOF
  CREATE DATABASE ecomdb;
  CREATE USER 'ecomuser'@'localhost' IDENTIFIED BY 'ecompassword';
  GRANT ALL PRIVILEGES ON *.* TO 'ecomuser'@'localhost';
  FLUSH PRIVILEGES;
EOF
sudo mysql < setup-db.sql

# Carregando inventário no banco de dados
color green "Configurando banco de dados"
cat > db-load-script.sql <<-EOF
USE ecomdb;
CREATE TABLE products (id mediumint(8) unsigned NOT NULL auto_increment,Name varchar(255) default NULL,Price varchar(255) default NULL, ImageUrl varchar(255) default NULL,PRIMARY KEY (id)) AUTO_INCREMENT=1;

INSERT INTO products (Name,Price,ImageUrl) VALUES ("Laptop","100","c-1.png"),("Drone","200","c-2.png"),("VR","300","c-3.png"),("Tablet","50","c-5.png"),("Watch","90","c-6.png"),("Phone Covers","20","c-7.png"),("Phone","80","c-8.png"),("Laptop","150","c-4.png");

EOF

sudo mysql < db-load-script.sql
# Teste de inventário do bancode dados

mysql_db_results=$(sudo mysql -e "use ecomdb; select * from products;")

if [[ $mysql_db_results == *Laptop* ]]
then
  color "green" "Inventory data loaded into MySQl"
else
  color "red" "Inventory data not loaded into MySQl"
  exit 1
fi

# Instalação do servidor web
color green "Instalacao do servidor web"
sudo yum install -y httpd php php-mysqlnd

# Configuração de regras do FirewallD para o servidor web
color green "Configuracao do FirewallD"
sudo firewall-cmd --permanent --zone=public --add-port=80/tcp
sudo firewall-cmd --reload
# Checar de a porta 80 está devidamente configurada no FirewallD
check_ports 80

# Mudando o arquivo de idex.html para index.php
sudo sed -i 's/index.html/index.php/g' /etc/httpd/conf/httpd.conf

# Iniciar o servidor web
color green "Iniciando o servidor web"
sudo service httpd start
sudo systemctl enable httpd
# Teste se o servidor web está rodando e habilitado
teste_service httpd
# Download do código do site fictício
color green " Baixando o GIT"
sudo yum install -y git
color green " Baixando o codigo do site ficticio"
sudo git clone https://github.com/kodekloudhub/learning-app-ecommerce.git /var/www/html/

color green "Atualizando index.php para localhost"
sudo sed -i 's/172.20.1.101/localhost/g' /var/www/html/index.php

color green "-- a configuração do servidor web esta completa--------"

# Testando a verificação dos itens no site
web_page=$(curl http://localhost)

for item in Laptop Drone VR Watch Phone
do
  check_item "$web_page" $item
done
