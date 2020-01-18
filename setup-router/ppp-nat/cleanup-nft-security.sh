#!/bin/bash

nft list table inet security_firewall > /dev/null 2>&1 ;
if [ $? -eq 0 ]; then
    nft delete table inet security_firewall
fi
