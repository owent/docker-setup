#!/bin/bash

# setup sshd
sed -i -r 's/required(\s*)pam_loginuid.so/optional\1pam_loginuid.so/g' /etc/pam.d/ssh* ;

sed -i -r 's/^\s*#?\s*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*RSAAuthentication.*/RSAAuthentication yes/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*X11Forwarding.*/X11Forwarding yes/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*AllowAgentForwarding.*/AllowAgentForwarding yes/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*TCPKeepAlive.*/TCPKeepAlive yes/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*ListenAddress\s*(.*)/#ListenAddress \1/' /etc/ssh/sshd_config
sed -i -r 's/^\s*#?\s*PermitUserEnvironment.*/PermitUserEnvironment yes/' /etc/ssh/sshd_config
sed -i '$!N; /^\(.*\)\n\1$/!P; D' /etc/ssh/sshd_config

# sed -i -r 's/^\s*#?\s*Port\s*22/Port 36000/' /etc/ssh/sshd_config

systemctl enable sshd
# systemctl start sshd
# systemctl status sshd
