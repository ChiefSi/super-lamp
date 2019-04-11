#!/bin/bash -e

function message()
{
	printf '\e[1m\e[38;5;27m%s\e[0m\n' "${1}"
}

function print_help()
{
	cat <<EOF
Usage: $0 <DIRECTORY> [-h|--help]
	   Generate certificate authority files/scripts in DIRECTORY

EOF
}

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
POSITIONAL=()

OPENSSL_CNF="${DIR}/root.cnf.in"

while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-h|--help)
			shift
			print_help
			exit 0
		;;
		*)
			POSITIONAL+=("$1")
			shift
		;;
	esac
done

set -- "${POSITIONAL[@]}"

OUTPUT=
if [ $# -ge 1 ]; then
	OUTPUT="${1}"
	[ ! -d "${OUTPUT}" ] && mkdir -p "${OUTPUT}"
	[ "$(ls -A "${OUTPUT}")" ] && echo "Warning: Destination directory not empty"
else
	print_help
	exit 1
fi

pushd "${OUTPUT}" >/dev/null

mkdir certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial

sed "s#%{DIRECTORY}#${OUTPUT}#g" "${OPENSSL_CNF}" > openssl.cnf

message "Generating CA private key"
openssl genrsa -aes256 -out private/ca.key.pem 4096
chmod 400 private/ca.key.pem

message "Generating CA certificate"
openssl req -config openssl.cnf \
	  -key private/ca.key.pem \
	  -new -x509 -days 7300 -sha256 -extensions v3_ca \
	  -out certs/ca.cert.pem
chmod 444 certs/ca.cert.pem

message ""
openssl x509 -noout -text \
	-certopt no_pubkey -certopt no_sigdump \
	-nameopt multiline \
	-in certs/ca.cert.pem

popd >/dev/null
