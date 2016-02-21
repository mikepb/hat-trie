#!/usr/bin/env python
# encoding: utf-8
# filename: profile.py

import pstats, cProfile

import pyximport
pyximport.install()

from speed import *

cProfile.runctx("benchmark()", globals(), locals(), "Profile.prof")

s = pstats.Stats("Profile.prof")
s.strip_dirs().sort_stats("time").print_stats()
