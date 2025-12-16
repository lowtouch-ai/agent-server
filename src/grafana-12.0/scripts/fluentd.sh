echo "=============================="
echo " td-agent Installation Script "
echo "=============================="
echo "This script requires superuser access to install apt packages."
echo "You will be prompted for your password by sudo."

  curl https://packages.treasuredata.com/GPG-KEY-td-agent | apt-key add -

  # add treasure data repository to apt
  echo "deb http://packages.treasuredata.com/3/ubuntu/bionic/ bionic contrib" > /etc/apt/sources.list.d/treasure-data.list

  # update your sources
  apt-get update

  # install the toolbelt
  apt-get install -y td-agent

# message
if [ $? -eq 0 ]; then
  echo ""
  echo "Installation completed. Happy Logging!"
  echo ""
else
  echo ""
  echo "Installation incompleted. Check above messages."
  echo ""
fi
