from setuptools import setup
from Cython.Build import cythonize

setup(
    name="whattheflux_core",
    ext_modules=cythonize(
        ["whattheflux_core.py", "whattheflux_web.py"],
        compiler_directives={
            "language_level": "3",
            "embedsignature": False,
        },
    ),
)
