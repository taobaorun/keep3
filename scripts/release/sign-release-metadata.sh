#!/bin/sh
set -eu

fail() {
  printf 'sign-release-metadata: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  sign-release-metadata.sh generate-fixture-key --private-key PATH --public-key PATH
  sign-release-metadata.sh sign --input JSON --output JSON --private-key PATH|- --key-id ID
  sign-release-metadata.sh verify --input JSON --public-key PATH --expected-key-id ID

Fixture-key generation is for local tests only. Production private keys must be
provided through a protected file or standard input and must never be committed.
USAGE
  exit 64
}

canonicalize_without_signature() {
  /usr/bin/ruby -rjson -e '
    def canonical(value)
      case value
      when Hash
        value.keys.sort.each_with_object({}) do |key, result|
          result[key] = canonical(value.fetch(key))
        end
      when Array
        value.map { |entry| canonical(entry) }
      else
        value
      end
    end

    document = JSON.parse(File.read(ARGV.fetch(0)))
    abort "document root must be an object" unless document.is_a?(Hash)
    document.delete("signature")
    File.binwrite(ARGV.fetch(1), JSON.generate(canonical(document)))
  ' "$1" "$2"
}

run_crypto() {
  xcrun swift - "$@" <<'SWIFT'
import CryptoKit
import Darwin
import Foundation

enum CryptoError: Error, CustomStringConvertible {
  case invalidArguments
  case invalidPEM(String)
  case invalidSignature

  var description: String {
    switch self {
    case .invalidArguments:
      return "invalid crypto arguments"
    case .invalidPEM(let label):
      return "invalid \(label) PEM"
    case .invalidSignature:
      return "Ed25519 signature verification failed"
    }
  }
}

let privateKeyPrefix = Data([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
  0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
])
let publicKeyPrefix = Data([
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03,
  0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
])

func pem(label: String, der: Data) -> String {
  let body = der.base64EncodedString(options: [.lineLength64Characters])
  return "-----BEGIN \(label)-----\n\(body)\n-----END \(label)-----\n"
}

func readPEM(path: String, label: String, prefix: Data) throws -> Data {
  let contents = try String(contentsOfFile: path, encoding: .utf8)
  let begin = "-----BEGIN \(label)-----"
  let end = "-----END \(label)-----"
  guard contents.contains(begin), contents.contains(end) else {
    throw CryptoError.invalidPEM(label)
  }
  let body = contents
    .components(separatedBy: .newlines)
    .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
    .joined()
  guard let der = Data(base64Encoded: body), der.starts(with: prefix),
    der.count == prefix.count + 32
  else {
    throw CryptoError.invalidPEM(label)
  }
  return der.dropFirst(prefix.count)
}

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard let operation = arguments.first else {
    throw CryptoError.invalidArguments
  }

  switch operation {
  case "generate":
    guard arguments.count == 3 else { throw CryptoError.invalidArguments }
    let privateKey = Curve25519.Signing.PrivateKey()
    let privateDER = privateKeyPrefix + privateKey.rawRepresentation
    let publicDER = publicKeyPrefix + privateKey.publicKey.rawRepresentation
    try pem(label: "PRIVATE KEY", der: privateDER).write(
      toFile: arguments[1], atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: arguments[1])
    try pem(label: "PUBLIC KEY", der: publicDER).write(
      toFile: arguments[2], atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644], ofItemAtPath: arguments[2])

  case "sign":
    guard arguments.count == 4 else { throw CryptoError.invalidArguments }
    let rawKey = try readPEM(
      path: arguments[1], label: "PRIVATE KEY", prefix: privateKeyPrefix)
    let privateKey = try Curve25519.Signing.PrivateKey(
      rawRepresentation: rawKey)
    let message = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    let signature = try privateKey.signature(for: message)
    try signature.base64EncodedString().write(
      toFile: arguments[3], atomically: true, encoding: .utf8)

  case "verify":
    guard arguments.count == 5 else { throw CryptoError.invalidArguments }
    let rawKey = try readPEM(
      path: arguments[1], label: "PUBLIC KEY", prefix: publicKeyPrefix)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    let message = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    let encodedSignature = try String(
      contentsOfFile: arguments[3], encoding: .utf8)
    guard let signature = Data(base64Encoded: encodedSignature),
      publicKey.isValidSignature(signature, for: message)
    else {
      throw CryptoError.invalidSignature
    }

  default:
    throw CryptoError.invalidArguments
  }
} catch {
  FileHandle.standardError.write(Data("metadata crypto: \(error)\n".utf8))
  exit(1)
}
SWIFT
}

mode=${1-}
test -n "$mode" || usage
shift

case "$mode" in
  generate-fixture-key)
    private_key=''
    public_key=''
    while test "$#" -gt 0; do
      case "$1" in
        --private-key) private_key=${2-}; shift 2 ;;
        --public-key) public_key=${2-}; shift 2 ;;
        *) usage ;;
      esac
    done
    test -n "$private_key" || fail "--private-key is required"
    test -n "$public_key" || fail "--public-key is required"
    test "$private_key" != '-' || fail "fixture private key needs a file path"
    umask 077
    run_crypto generate "$private_key" "$public_key"
    ;;

  sign)
    input=''
    output=''
    private_key=''
    key_id=''
    while test "$#" -gt 0; do
      case "$1" in
        --input) input=${2-}; shift 2 ;;
        --output) output=${2-}; shift 2 ;;
        --private-key) private_key=${2-}; shift 2 ;;
        --key-id) key_id=${2-}; shift 2 ;;
        *) usage ;;
      esac
    done
    test -f "$input" || fail "--input must name an existing JSON file"
    test -n "$output" || fail "--output is required"
    test -n "$private_key" || fail "--private-key is required"
    test -n "$key_id" || fail "--key-id is required"
    printf '%s\n' "$key_id" | /usr/bin/ruby -e '
      value = STDIN.read.strip
      exit(value.match?(/\Akeep3-release-metadata-[a-z0-9-]+\z/) ? 0 : 1)
    ' || fail "invalid metadata key identifier"

    temporary_directory=$(mktemp -d /tmp/keep3-metadata-sign-XXXXXX)
    trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
    canonical_file="$temporary_directory/canonical.json"
    signature_file="$temporary_directory/signature.txt"
    if test "$private_key" = '-'; then
      private_key="$temporary_directory/private-key.pem"
      umask 077
      cat > "$private_key"
      chmod 600 "$private_key"
    fi
    test -f "$private_key" || fail "metadata private key file does not exist"

    canonicalize_without_signature "$input" "$canonical_file"
    run_crypto sign "$private_key" "$canonical_file" "$signature_file"
    /usr/bin/ruby -rjson -e '
      document = JSON.parse(File.read(ARGV.fetch(0)))
      key_id = ARGV.fetch(3)
      signed = document.fetch("signed")
      abort "signed keyId does not match --key-id" unless signed["keyId"] == key_id
      document.delete("signature")
      document["signature"] = {
        "algorithm" => "Ed25519",
        "keyId" => key_id,
        "value" => File.read(ARGV.fetch(1)).strip
      }
      File.write(ARGV.fetch(2), JSON.pretty_generate(document) + "\n")
    ' "$input" "$signature_file" "$output" "$key_id" \
      || fail "could not create signed metadata envelope"
    ;;

  verify)
    input=''
    public_key=''
    expected_key_id=''
    while test "$#" -gt 0; do
      case "$1" in
        --input) input=${2-}; shift 2 ;;
        --public-key) public_key=${2-}; shift 2 ;;
        --expected-key-id) expected_key_id=${2-}; shift 2 ;;
        *) usage ;;
      esac
    done
    test -f "$input" || fail "--input must name an existing JSON file"
    test -f "$public_key" || fail "--public-key must name an existing PEM file"
    test -n "$expected_key_id" || fail "--expected-key-id is required"

    temporary_directory=$(mktemp -d /tmp/keep3-metadata-verify-XXXXXX)
    trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
    canonical_file="$temporary_directory/canonical.json"
    signature_file="$temporary_directory/signature.txt"
    canonicalize_without_signature "$input" "$canonical_file"
    /usr/bin/ruby -rjson -e '
      document = JSON.parse(File.read(ARGV.fetch(0)))
      signature = document.fetch("signature")
      abort "unsupported signature algorithm" unless signature["algorithm"] == "Ed25519"
      expected = ARGV.fetch(2)
      abort "signature key identifier mismatch" unless signature["keyId"] == expected
      abort "signed key identifier mismatch" unless document.fetch("signed")["keyId"] == expected
      File.write(ARGV.fetch(1), signature.fetch("value"))
    ' "$input" "$signature_file" "$expected_key_id" \
      || fail "invalid metadata signature envelope"
    run_crypto verify "$public_key" "$canonical_file" "$signature_file" unused
    ;;

  *) usage ;;
esac
