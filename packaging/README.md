<!--
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 -->

# CloudStack RPM and DEB packaging
This directory contains all the required scripts and tools needed to build RPM and DEB packages for Apache CloudStack.

These scripts are also used by the CloudStack team to build packages for the official release of CloudStack.

# Requirements
The RPM and DEB packages have dependencies on versions of specific libraries. Due to these dependencies the following distributions and their versions are supported by the packages.

* CentOS / RHEL: 8 and 9
* Ubuntu: 20.04, 22.04, 24.04
* Debian 12 (Bookworm, untested!)

# Building
Using the scripts in the *packaging* directory the RPM and DEB packages can be build.

## DEB
If you simply want to build packages go to the root directory of your CloudStack source code and run:

``dpkg-buildpackage``

This will build packages for the current distribution version you are running. If you run this on a Ubuntu 16.04 system the packages will be tailored for Ubuntu 16.04 and will not install on Ubuntu 14.04.

### Building cross-distribution
If you want to build packages for a different distribution run the *build-deb.sh* script. This will build packages with the current distribution as a suffix to the package names. E.g. *cloudstack-agent_4.9.0~xenial_all.deb*

Using a Docker image you can build packages for a distribution you are not running.

The following commands assume that the CloudStack source is present in **/tmp/cloudstack** on the system you are running these commands on.

``docker run -ti -v /tmp:/src ubuntu:16.04 /bin/bash -c "apt-get update && apt-get install -y dpkg-dev python debhelper openjdk-8-jdk genisoimage python-mysql.connector maven lsb-release devscripts && /src/cloudstack/packaging/build-deb.sh"``

``docker run -ti -v /tmp:/src ubuntu:14.04 /bin/bash -c "apt-get update && apt-get install -y dpkg-dev python debhelper openjdk-7-jdk genisoimage python-mysql.connector maven lsb-release devscripts && /src/cloudstack/packaging/build-deb.sh"``

``docker run -ti -v /tmp:/src ubuntu:22.04 /bin/bash -c "apt-get update && apt-get install -y software-properties-common &&apt-add-repository universe --yes && apt-get update && apt-get install -y dpkg-dev debhelper lsb-release devscripts openjdk-11-jdk libws-commons-util-java genisoimage libcommons-codec-java libcommons-httpclient-java liblog4j1.2-java maven python3 python3-mysql.connector python3-setuptools python-setuptools python3-openssl python3-dev libffi-dev build-essential libssl-dev libffi-dev fakeroot python-is-python3 && curl -sL https://deb.nodesource.com/setup_14.x | bash - && apt-get install -y nodejs &&  /src/cloudstack/packaging/build-deb.sh"``

The commands above will generate Ubuntu 14.04, 16.04, and 22.04 packages which you will find in */tmp* on your system after the build succeeds.

## RPM
The *package.sh* script can be used to build RPM packages for CloudStack. In the *packaging* script you can run the following command:

``./package.sh --pack oss --distribution el8``

### namuVIRT: per-distribution spec directories

`packaging/el9`, `packaging/centos8` and `packaging/suse15` are symlinks to `packaging/el8`,
so a single spec serves them. `packaging/el10` is a **real directory** because EL10 needs
separate handling (no `java-17-openjdk` in the repositories, no dnf modularity).

Rules when touching either spec:

* An upstream `cloud.spec` change (subpackages, `Requires`, `%files`, `%build`) must be applied
  to **both** `packaging/el8/cloud.spec` and `packaging/el10/cloud.spec`.
* Verify afterwards: `diff packaging/el8/cloud.spec packaging/el10/cloud.spec`
* Allowed differences, as of the Rocky 10 support commit:

  | Line | el8 | el10 | Why |
  |------|-----|------|-----|
  | `%global cspkgdir` | `packaging/el8` | `packaging/el10` | Each spec reads its own data files (`replace.properties`, `cloudstack-sccs`, `cloud-ipallocator.rc`, `cloud.limits`, `filelimit.conf`) |
  | `Requires` of `cloudstack-management` (ISO tool) | `(genisoimage or mkisofs)` | `/usr/bin/mkisofs` | EL10 ships neither package name; `xorriso` provides only the file |
  | `%posttrans common` python site dir | `distutils.sysconfig.get_python_lib(1)` | `sysconfig.get_path('platlib', 'posix_prefix', ...)` | Python 3.12 on EL10 has no `distutils`; without this the scriptlet silently skips copying `cloudutils` |

* A change that is genuinely EL10-only (for example a `Requires` that does not exist on EL10)
  goes into `packaging/el10/cloud.spec` alone and is added to the table above.
* `packaging/el10` intentionally omits `cloudstack-agent.te`: the spec does not reference it.

`./build/rocky.sh` picks the directory from the build host (`el<VERSION_ID major>`) and fails
early when `packaging/<dist>/cloud.spec` is missing. See `build/README.md`.

