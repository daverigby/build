#!/bin/bash
#          
#          run by jenkins jobs: 'mobile_functional_tests_ios_master'
#                               'mobile_functional_tests_ios_100'
#          
#          called with paramters:
#             
#             RELEASE           0.0.0, 1.0.0
#             LITESERV_VERSION  set by build_cblite_ios_master, _100
#             SYNCGATE_VERSION  ( hard-coded to run on macosx-x64 )
#             EDITION
#             
source ~jenkins/.bash_profile
export PATH=/usr/local/bin:$PATH
export DISPLAY=:0
set -e

LOG_TAIL=-24


function usage
    {
    echo -e "\nuse:  ${0}   release  liteserv.version   syncgateway.version  edtion\n\n"
    }
if [[ ! ${1} ]] ; then usage ; exit 99 ; fi
RELEASE=${1}

if [[ ! ${2} ]] ; then usage ; exit 88 ; fi
SYNCGATE_VERSION=${2}

if [[ ! ${3} ]] ; then usage ; exit 77 ; fi
LITESERV_VERSION=${3}

if [[ ! ${4} ]] ; then usage ; exit 66 ; fi
EDITION=${4}


PLATFORM=darwin-amd64

if [[ ${EDITION} =~ 'community' ]]
  then
    SGW_PKG=couchbase-sync-gateway_${SYNCGATE_VERSION}_macosx-x86_64-${EDITION}.tar.gz
else
    SGW_PKG=couchbase-sync-gateway_${SYNCGATE_VERSION}_macosx-x86_64.tar.gz
fi
    LIT_PKG=couchbase-lite-ios-${EDITION}_${LITESERV_VERSION}.zip

SGW_PKGSTORE=s3://packages.couchbase.com/builds/mobile/sync_gateway/${RELEASE}/${SYNCGATE_VERSION}
LIT_PKGSTORE=s3://packages.couchbase.com/builds/mobile/ios/${RELEASE}/${LITESERV_VERSION}
export SGW_PKGSTORE
export LIT_PKGSTORE

GET_CMD="s3cmd get"


LOG_DIR=${WORKSPACE}/${EDITION}_logs
if [[ -e ${LOG_DIR} ]] ; then rm -rf ${LOG_DIR} ; fi
mkdir -p ${LOG_DIR}


AUT_DIR=${WORKSPACE}/app-under-test
if [[ -e ${AUT_DIR} ]] ; then rm -rf ${AUT_DIR} ; fi
mkdir -p ${AUT_DIR}/liteserv
mkdir -p ${AUT_DIR}/sync_gateway

LITESERV_DIR=${AUT_DIR}/liteserv
SYNCGATE_DIR=${AUT_DIR}/sync_gateway

export LITESERV_PATH=${LITESERV_DIR}/LiteServ.app/Contents/MacOS/LiteServ
export SYNCGATE_PATH=${SYNCGATE_DIR}/couchbase-sync-gateway/bin/sync_gateway

export TAP_TIMEOUT=40000

DOWNLOAD=${AUT_DIR}/download

echo ============================================ `date`
env | grep -iv password | grep -iv passwd | sort

echo ============================================ install liteserv
rm   -rf ${DOWNLOAD}
mkdir -p ${DOWNLOAD}
pushd    ${DOWNLOAD} 2>&1 > /dev/null

${GET_CMD} ${LIT_PKGSTORE}/${LIT_PKG}

cd ${LITESERV_DIR}
if [[ ! -e ${DOWNLOAD}/${LIT_PKG} ]]
    then
    echo "LiteServ download failed, cannot find ${DOWNLOAD}/${LIT_PKG}"
    exit 99
fi
unzip   -q ${DOWNLOAD}/${LIT_PKG}
                                                         # want all of the zip file contents
popd                 2>&1 > /dev/null

echo ============================================ download sync_gateway
rm   -rf ${SYNCGATE_DIR}
mkdir -p ${SYNCGATE_DIR}
pushd    ${SYNCGATE_DIR} 2>&1 > /dev/null

${GET_CMD} ${SGW_PKGSTORE}/${SGW_PKG}
STATUS=$?
if [[ ${STATUS} > 0 ]] ; then echo "FAILED to download ${SGW_PKG}" ; exit ${STATUS} ; fi

echo ============================================ install sync_gateway
tar xvf    ${SYNCGATE_DIR}/${SGW_PKG}

popd                 2>&1 > /dev/null

cd ${WORKSPACE}
echo ============================================ sync cblite-tests
if [[ ! -d cblite-tests ]] ; then git clone https://github.com/couchbaselabs/cblite-tests.git ; fi
cd cblite-tests
git pull
git show --stat

echo ============================================ npm install
mkdir -p tmp/single

( npm install  2>&1  )                       >> ${LOG_DIR}/npm_install.log

if  [[ -e ${LOG_DIR}/npm_install.log ]]
    then
    echo
    echo "===================================== ${LOG_DIR}/npm_install.log"
    echo ". . ."
    tail ${LOG_TAIL}                            ${LOG_DIR}/npm_install.log
fi

echo ============================================ killing any hanging LiteServ
killall LiteServ || true

# echo ===================================================================================== starting ${LITESERV_PATH}
# ${LITESERV_PATH} | tee  ${WORKSPACE}/liteserv.log & 
#
# echo ===================================================================================== starting ./node_modules/.bin/tap
# export TAP_TIMEOUT=500
# ./node_modules/.bin/tap ./tests       1> ${WORKSPACE}/results.log  2> ${WORKSPACE}/gateway.log

echo ============================================ npm test
( npm test     2>&1  )                       >> ${LOG_DIR}/npm_test_results.log

if  [[ -e ${LOG_DIR}/npm_test_results.log ]]
    then
    echo
    echo "===================================== ${LOG_DIR}/npm_test_results.log"
    echo ". . ."
    tail ${LOG_TAIL}                            ${LOG_DIR}/npm_test_results.log
fi

echo ============================================ killing any hanging LiteServ
killall LiteServ || true

FAILS=`cat ${LOG_DIR}/npm_test_results.log | grep 'npm ERR!' | wc -l`
if [[ $((FAILS)) > 0 ]] 
  then
    echo ============================================ exit: ${FAILS}
    exit ${FAILS}
  else
    echo ============================================ DONE
    exit ${FAILS}
fi
