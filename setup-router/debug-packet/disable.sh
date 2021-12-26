#!/bin/bash

nft list table inet debug >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete table inet debug
fi

nft list table bridge debug >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  nft delete table bridge debug
fi
