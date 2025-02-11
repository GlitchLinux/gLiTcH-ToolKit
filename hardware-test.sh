#!/bin/bash
sudo memtester 1G 1
sudo smartctl -a /dev/sda
