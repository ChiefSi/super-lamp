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

function prompt_and_store_passphrase()
{
	OUTPUT="${1}"
	ATTEMPT=0
	while [ $ATTEMPT -lt 3 ]; do

		echo -n "Enter passphrase: "
		read -s PASS1
		echo

		echo -n "Confirm passphrase: "
		read -s PASS2
		echo

		if [ ${PASS1} = ${PASS2} ]; then
			echo "${PASS1}" > "${OUTPUT}"
			break
		else
			echo "Passwords do not match"
			ATTEMPT=$[$ATTEMPT+1]
			[ $ATTEMPT -gt 3 ] && exit 1
		fi
	done
}

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
POSITIONAL=()

ROOT_SSL_CNF="${DIR}/root.cnf.in"
GENERATE_INTERMEDIATE_SCRIPT="${DIR}/generate-intermediate-ca.sh.in"
INTERMEDIATE_SSL_CNF_TEMPLATE="${DIR}/intermediate.cnf.in"

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

sed "s#%{DIRECTORY}#${OUTPUT}#g" "${ROOT_SSL_CNF}" > openssl.cnf

mkdir intermediates templates
cp "${INTERMEDIATE_SSL_CNF_TEMPLATE}" templates/
sed "s#%{SIGNING_CA_DIR}#${OUTPUT}#g" "${GENERATE_INTERMEDIATE_SCRIPT}" > generate-intermediate-ca.sh
chmod 755 generate-intermediate-ca.sh

message "Generating CA private key (private/ca.key.pem)"
prompt_and_store_passphrase private/passphrase
openssl genrsa -aes256 -out private/ca.key.pem -passout file:private/passphrase 4096
chmod 400 private/ca.key.pem

message "Generating CA certificate (certs/ca.cert.pem)"
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
