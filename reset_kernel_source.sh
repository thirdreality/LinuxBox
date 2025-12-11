#!/bin/bash

cd /root/linuxbox/LinuxBox/cache/sources/linux-mainline/linux-5.15.y

git status -uno --porcelain --ignore-submodules=all
git status -s | wc -l


git checkout -f -q HEAD
git clean -qdf


git status -uno --porcelain --ignore-submodules=all
git status -s | wc -l
