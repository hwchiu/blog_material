#!/bin/bash
set -x
git clone https://github.com/hwchiu/blog_material.git

cd blog_material
./env.sh install
./env.sh create
./env.sh verify
