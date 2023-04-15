# nimtemplate:scroll:

A template to jump start your Nim library or project.

* Tests using [balls](https://github.com/disruptek/balls)
* GitHub Actions [workflows](../../actions)
  * Runs tests on multiple OSes and ISAs
  * Builds and deploys [API reference on GitHub Pages](https://Gruruya.github.io/nimtemplate/nimtemplate.html)

_Click [here](../../../nimtemplate/generate) to begin_  

---
[![GitHub CI](../../actions/workflows/build.yml/badge.svg?branch=master)](../../actions/workflows/build.yml)
[![Minimum supported Nim version](https://img.shields.io/badge/Nim-1.6.12+-informational?logo=Nim&labelColor=232733&color=F3D400)](https://nim-lang.org)
[![License](https://img.shields.io/github/license/Gruruya/nimtemplate?logo=GNU&logoColor=000000&labelColor=FFFFFF&color=663366)](LICENSE.md)

Usage
---
You're gonna want to change the names in the project. If you're on Linux you can do it like this:
```sh
# Change these to define your new project name and GitHub username
export GHUSER=Gruruya
export PROJNAME=nimtemplate

# Change text in the repo
sed -i "s/Gruruya/$GHUSER/g" README.md nimtemplate.nimble
sed -i "s/nimtemplate/$PROJNAME/g" README.md nimtemplate.nimble src/nimtemplate.nim tests/test.nim .github/workflows/documentation.yml
rename nimtemplate "$PROJNAME" * src/*
```

#### Note on the License
You can change the license freely in your project generated with this template.
