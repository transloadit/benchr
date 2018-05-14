#!/usr/bin/env bash
# Copyright (c) 2018, Transloadit Ltd.
# Authors:
#  - Kevin van Zonneveld <kevin@transloadit.com>

set -o pipefail
set -o errexit
set -o nounset
# set -o xtrace

# Set magic variables for current FILE & DIR
# __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# __file="${__dir}/$(basename "${0}")"
# __base="$(basename ${__file} .sh)"
# __root="$(cd "$(dirname "${__dir}")" && pwd)"

scenario=${SCENARIO:-1}

tusdVersion=${TUSD_VERSION:-0.10.0}
tusdSource="releases"
tusdPid="-1"
tusdDataDir="/tmp/benchr/data"
tusJsClientVersion=${TUSJSCLIENT_VERSION:-v1.5.1}
tusJsClientSource="releases"
if [[ "${OSTYPE}" = "darwin"* ]]; then
  arch="darwin_amd64.zip"
else
  arch="linux_amd64.tar.gz"
fi

mkdir -p /tmp/benchr
pushd /tmp/benchr 1>&2
  # Install tusd if needed
  if [ "${tusdSource}" = "releases" ]; then
    [ -f "tusd_${arch}.zip" ] || wget "https://github.com/tus/tusd/releases/download/${tusdVersion}/tusd_${arch}"
    [ -f "${PWD}/tusd_${arch}/tusd" ] || unzip "tusd_${arch}.zip"
    tusdBin="${PWD}/tusd_${arch}/tusd"
  elif [ "${tusdSource}" = "git" ]; then
    [ -d tusd ] || git clone git@github.com:tus/tusd.git 1>&2
    cd tusd
    git pull 1>&2
    git checkout "${tusdVersion}" 1>&2
    go build -o tusd cmd/tusd/main.go 1>&2
    tusdBin="${PWD}/tusd"
  else 
    echo "Unkown tusdSource: '${tusdSource}'" 1>&2
    exit 1
  fi

  # Install tus-js-client if needed
  if [ "${tusJsClientSource}" = "releases" ]; then
    mkdir -p node_modules
    echo '{}' > package.json
    yarn add "tus-js-client@${tusJsClientVersion}" 1>&2 || npm install "tus-js-client@${tusJsClientVersion}" 1>&2
    tusJsClientModule="${PWD}/node_modules/tus-js-client" 
  elif [ "${tusJsClientSource}" = "git" ]; then
    [ -d tus-js-client ] || git clone git@github.com:tus/tus-js-client.git 1>&2
    cd tus-js-client
    git pull 1>&2
    git checkout "${tusJsClientVersion}" 1>&2
    make build 1>&2
    tusJsClientModule="${PWD}" 
  else 
    echo "Unkown tusJsClientSource: '${tusJsClientSource}'" 1>&2
    exit 1
  fi

  # Fetch 1GB file
  [ -f 1GB.zip ] || wget "http://speedtest.tele2.net/1GB.zip" 1>&2
  payload="${PWD}/1GB.zip"

  echo "
var fs = require('fs');
var tus = require('${tusJsClientModule}');

var path = '${payload}';
var file = fs.createReadStream(path);
var size = fs.statSync(path).size;

var options = {
  endpoint: 'http://localhost:1080/files/',
  resume: true,
  metadata: {
      filename: '$(basename "${payload}")'
  },
  uploadSize: size,
  onError: function (error) {
    throw error;
  },
  onProgress: function (bytesUploaded, bytesTotal) {
    var percentage = (bytesUploaded / bytesTotal * 100).toFixed(2);
    console.error(bytesUploaded, bytesTotal, percentage + '%');
  },
  onSuccess: function () {
    console.error('Upload finished:', upload.url);
    var stop = +Date.now()
    var durationSec = (stop - start) / 1000
    var bit = size * 8
    var mbit = bit / 1000 / 1000
    var mbitSec = mbit / durationSec
    console.log('' + mbitSec + ' mbit/s')
  }
};

var upload = new tus.Upload(file, options);
var start = +Date.now()
upload.start()
" > client.js
  tusJsClientBin="${PWD}/client.js"   
popd 1>&2

ls "${tusdBin}" 1>&2
ls "${tusJsClientModule}" 1>&2
ls "${tusJsClientBin}" 1>&2

function __cleanup_before_exit () {
  if [ "${tusdPid}" != "-1" ]; then
    echo "Killing tusd ... " 1>&2
    kill -9 "${tusdPid}" 1>&2
    echo "Cleaning up storage ... " 1>&2
    rm -rf "${tusdDataDir}" 1>&2
  fi
}
trap __cleanup_before_exit EXIT

if [ "${scenario}" = "1" ]; then
  "${tusdBin}" -dir "${tusdDataDir}" 1>&2 &
  tusdPid=${?}
  sleep 0.5 1>&2
  node "${tusJsClientBin}"
elif [ "${scenario}" = "2" ]; then
  # for instance, set different tcp window size here
  "${tusdBin}" -dir "${tusdDataDir}" 1>&2 &
  tusdPid=${?}
  sleep 0.5 1>&2
  node "${tusJsClientBin}"
else
  echo "Unkown scenario: '${scenario}'" 1>&2
  exit 1
fi
