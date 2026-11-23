#!/usr/bin/env python3
# Copyright (c) 2026 Michael Suenens - Ancilux Services. All rights reserved.
import importlib.util, glob, os

_dir = os.path.dirname(os.path.abspath(__file__))
_so  = glob.glob(os.path.join(_dir, "whattheflux_web*.so"))

if _so:
    _spec = importlib.util.spec_from_file_location("whattheflux_web", _so[0])
    whattheflux_web = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(whattheflux_web)
else:
    import whattheflux_web

whattheflux_web.main()
