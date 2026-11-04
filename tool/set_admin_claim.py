"""Memberi atau mencabut hak administrator IMAGO pada akun Firebase Auth.

Hak admin disimpan sebagai custom claim `admin: true` pada token Firebase.
Claim inilah yang diperiksa aplikasi (AuthService) dan ditegakkan oleh
firestore.rules. Claim hanya bisa diubah lewat Admin SDK, tidak dari aplikasi.

Prasyarat:
  pip install firebase-admin
  Unduh kunci service account dari Firebase Console
  (Project settings > Service accounts > Generate new private key).
  JANGAN commit berkas kunci itu ke git.

Pemakaian:
  python tool/set_admin_claim.py --key path/ke/service-account.json grant  admin_imago@peruri.co.id
  python tool/set_admin_claim.py --key path/ke/service-account.json revoke admin_imago@peruri.co.id
  python tool/set_admin_claim.py --key path/ke/service-account.json show   admin_imago@peruri.co.id

Setiap grant/revoke juga mencabut seluruh sesi aktif akun tersebut, sehingga
pengguna harus login ulang dan memperoleh token dengan claim terbaru.
"""

import argparse
import sys

import firebase_admin
from firebase_admin import auth, credentials


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--key", required=True, help="Berkas JSON service account")
    p.add_argument("action", choices=["grant", "revoke", "show"])
    p.add_argument("email")
    args = p.parse_args()

    firebase_admin.initialize_app(credentials.Certificate(args.key))
    user = auth.get_user_by_email(args.email)
    claims = dict(user.custom_claims or {})

    if args.action == "show":
        print(f"{user.email} (uid {user.uid}) claims: {claims}")
        return 0

    if args.action == "grant":
        claims["admin"] = True
    else:
        claims.pop("admin", None)

    auth.set_custom_user_claims(user.uid, claims or None)
    auth.revoke_refresh_tokens(user.uid)
    print(f"{args.action}: {user.email} -> claims {claims}; sesi aktif dicabut.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
