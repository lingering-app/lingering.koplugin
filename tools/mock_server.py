#!/usr/bin/env python3
"""
Lokale testserver voor de rooktest (tools/smoke.sh): OPDS-catalogus en kosync-API die altijd
hetzelfde teruggeven. Alleen de Python-standaardbibliotheek; alles wordt bij het starten in het
geheugen gemaakt (eigen testboeken, geen echte boeken). Stand van kosync begint elke start leeg.

  python3 -I tools/mock_server.py [--port 8765]

KOReader starten met:
  LINGERING_OPDS_URL=http://127.0.0.1:8765/opds
  LINGERING_SYNC_URL=http://127.0.0.1:8765/kosync
Account: gebruiker "test", wachtwoord "test" (OPDS: Basic auth; kosync: x-auth-key = md5).

Paden:
  /opds                      hoofdcatalogus (navigatie naar de mappen)
  /opds/folder/<id>          map met boeken (acquisitiefeed)
  /opds/book/<id>.epub       boek
  /opds/cover/<id>.png       omslag (ook als thumbnail)
  /kosync/users/auth         GET, 200 of 401
  /kosync/syncs/progress     PUT, stand wegschrijven
  /kosync/syncs/progress/<d> GET, stand ophalen ({} als er nog niets is)
  /dict/test-nl.zip          klein StarDict-woordenboek (voor de woordenboektest)
"""
import argparse
import base64
import hashlib
import io
import json
import struct
import time
import zipfile
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

USER, PASSWORD = "test", "test"
USERKEY = hashlib.md5(PASSWORD.encode()).hexdigest()

BOOKS = [
    # id, titel, auteur, kleur van de omslag
    ("1", "De Stille Haven", "Anna de Vries", (30, 90, 160)),
    ("2", "Het Lange Pad", "Bram Jansen", (180, 60, 40)),
    ("3", "Wind over de Polder", "Carla Smit", (40, 140, 80)),
    ("4", "Een Jaar aan Zee", "Daan Bakker", (200, 160, 30)),
    ("5", "De Laatste Trein", "Eva Visser", (110, 50, 140)),
    ("6", "Licht in de Winter", "Frank Mulder", (60, 60, 60)),
]
FOLDERS = [
    # id, titel, boeken
    ("all", "Al mijn boeken", ["1", "2", "3", "4", "5", "6"]),
    ("reading", "Aan het lezen", ["1", "2"]),
    ("toread", "Wil ik lezen", ["3", "4", "5"]),
    ("read", "Gelezen", ["6"]),
]

WORDS = ("de het een en van in is op dat zee wind licht haven pad trein winter polder jaar "
         "stil lang laatste water hemel weg huis boom vogel stad dorp land avond morgen").split()


def lorem(seed, words):
    out = []
    for i in range(words):
        out.append(WORDS[(seed * 7 + i * 13 + i // 5) % len(WORDS)])
    text = " ".join(out)
    return text[0].upper() + text[1:] + "."


def make_png(width, height, rgb):
    """Effen omslag met een lichtere band, als PNG (zonder externe bibliotheken)."""
    r, g, b = rgb
    light = bytes((min(255, r + 70), min(255, g + 70), min(255, b + 70)))
    dark = bytes((r, g, b))
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        band = height * 2 // 5 <= y < height * 3 // 5
        raw.extend((light if band else dark) * width)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def make_epub(book_id, title, author, cover_png):
    """Minimale EPUB 2 met twaalf hoofdstukken, inhoudsopgave (NCX) en omslag."""
    chapters = 12
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml",
                   '<?xml version="1.0"?><container version="1.0" '
                   'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
                   '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
                   '</rootfiles></container>')
        manifest, spine, nav = [], [], []
        for n in range(1, chapters + 1):
            paras = "".join("<p>%s</p>" % lorem(int(book_id) * 100 + n * 10 + p, 120) for p in range(14))
            z.writestr("OEBPS/c%d.xhtml" % n,
                       '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml">'
                       '<head><title>Hoofdstuk %d</title></head><body><h1>Hoofdstuk %d</h1>%s</body></html>'
                       % (n, n, paras))
            manifest.append('<item id="c%d" href="c%d.xhtml" media-type="application/xhtml+xml"/>' % (n, n))
            spine.append('<itemref idref="c%d"/>' % n)
            nav.append('<navPoint id="n%d" playOrder="%d"><navLabel><text>Hoofdstuk %d</text></navLabel>'
                       '<content src="c%d.xhtml"/></navPoint>' % (n, n, n, n))
        z.writestr("OEBPS/cover.png", cover_png)
        z.writestr("OEBPS/toc.ncx",
                   '<?xml version="1.0" encoding="utf-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
                   'version="2005-1"><head><meta name="dtb:uid" content="lingering-test-%s"/></head>'
                   '<docTitle><text>%s</text></docTitle><navMap>%s</navMap></ncx>'
                   % (book_id, escape(title), "".join(nav)))
        z.writestr("OEBPS/content.opf",
                   '<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" '
                   'unique-identifier="uid" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                   '<dc:identifier id="uid">lingering-test-%s</dc:identifier><dc:title>%s</dc:title>'
                   '<dc:creator>%s</dc:creator><dc:language>nl</dc:language><meta name="cover" content="cover"/>'
                   '</metadata><manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
                   '<item id="cover" href="cover.png" media-type="image/png"/>%s</manifest>'
                   '<spine toc="ncx">%s</spine></package>'
                   % (book_id, escape(title), escape(author), "".join(manifest), "".join(spine)))
    return buf.getvalue()


def make_dictionary():
    """Klein StarDict-woordenboek (ifo/idx/dict) in een zip, in een eigen map."""
    words = sorted({"haven": "Plek waar schepen veilig liggen.", "polder": "Ingedijkt laag land.",
                    "zee": "Groot zout water.", "winter": "Koudste seizoen van het jaar."}.items())
    dict_data, idx = b"", b""
    for word, meaning in words:
        data = meaning.encode()
        idx += word.encode() + b"\0" + struct.pack(">II", len(dict_data), len(data))
        dict_data += data
    ifo = ("StarDict's dict ifo file\nversion=2.4.2\nbookname=Lingering testwoordenboek\n"
           "wordcount=%d\nidxfilesize=%d\nsametypesequence=m\n" % (len(words), len(idx)))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("lingering-test-nl/test.ifo", ifo)
        z.writestr("lingering-test-nl/test.idx", idx)
        z.writestr("lingering-test-nl/test.dict", dict_data)
    return buf.getvalue()


COVERS = {book_id: make_png(300, 450, color) for book_id, _, _, color in BOOKS}
EPUBS = {book_id: make_epub(book_id, title, author, COVERS[book_id]) for book_id, title, author, _ in BOOKS}
DICTIONARY = make_dictionary()
PROGRESS = {}  # document → { percentage, progress, device, device_id, timestamp }

ATOM = "application/atom+xml;profile=opds-catalog"


def feed(base, feed_id, title, entries):
    return ('<?xml version="1.0" encoding="utf-8"?>'
            '<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">'
            '<id>%s</id><title>%s</title><updated>2026-01-01T00:00:00Z</updated>'
            '<link rel="self" href="%s/opds" type="%s"/>%s</feed>'
            % (feed_id, escape(title), base, ATOM, "".join(entries)))


def root_feed(base):
    entries = ['<entry><id>folder-%s</id><title>%s</title><updated>2026-01-01T00:00:00Z</updated>'
               '<link rel="subsection" href="%s/opds/folder/%s" type="%s;kind=acquisition"/></entry>'
               % (fid, escape(title), base, fid, ATOM) for fid, title, _ in FOLDERS]
    return feed(base, "root", "Lingering test", entries)


def folder_feed(base, folder_id):
    for fid, title, ids in FOLDERS:
        if fid == folder_id:
            entries = []
            for book_id, btitle, author, _ in BOOKS:
                if book_id in ids:
                    entries.append(
                        '<entry><id>book-%s</id><title>%s</title><author><name>%s</name></author>'
                        '<updated>2026-01-01T00:00:00Z</updated>'
                        '<link rel="http://opds-spec.org/acquisition" href="%s/opds/book/%s.epub" type="application/epub+zip"/>'
                        '<link rel="http://opds-spec.org/image" href="%s/opds/cover/%s.png" type="image/png"/>'
                        '<link rel="http://opds-spec.org/image/thumbnail" href="%s/opds/cover/%s.png" type="image/png"/>'
                        '</entry>' % (book_id, escape(btitle), escape(author), base, book_id, base, book_id, base, book_id))
            return feed(base, "folder-" + fid, title, entries)
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # stil, behalve fouten
        pass

    def send(self, status, body=b"", content_type="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def base(self):
        return "http://%s" % (self.headers.get("Host") or "127.0.0.1")

    def opds_authorized(self):
        expected = "Basic " + base64.b64encode(("%s:%s" % (USER, PASSWORD)).encode()).decode()
        return self.headers.get("Authorization") == expected

    def kosync_authorized(self):
        return self.headers.get("x-auth-user") == USER and self.headers.get("x-auth-key") == USERKEY

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/")
        if path.startswith("/opds"):
            if not self.opds_authorized():
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="lingering-test"')
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if path == "/opds":
                return self.send(200, root_feed(self.base()), ATOM)
            if path.startswith("/opds/folder/"):
                body = folder_feed(self.base(), path.rsplit("/", 1)[1])
                return self.send(200, body, ATOM) if body else self.send(404)
            if path.startswith("/opds/book/"):
                book = EPUBS.get(path.rsplit("/", 1)[1].replace(".epub", ""))
                return self.send(200, book, "application/epub+zip") if book else self.send(404)
            if path.startswith("/opds/cover/"):
                cover = COVERS.get(path.rsplit("/", 1)[1].replace(".png", ""))
                return self.send(200, cover, "image/png") if cover else self.send(404)
            return self.send(404)
        if path == "/kosync/users/auth":
            if self.kosync_authorized():
                return self.send(200, json.dumps({"authorized": "OK"}))
            return self.send(401, json.dumps({"message": "Unauthorized"}))
        if path.startswith("/kosync/syncs/progress/"):
            if not self.kosync_authorized():
                return self.send(401, json.dumps({"message": "Unauthorized"}))
            document = path.rsplit("/", 1)[1]
            record = PROGRESS.get(document)
            return self.send(200, json.dumps(dict(record, document=document) if record else {}))
        if path == "/dict/test-nl.zip":
            return self.send(200, DICTIONARY, "application/zip")
        return self.send(404)

    def do_HEAD(self):
        # KOReaders woordenboekdownload vraagt eerst de grootte op.
        if self.path.rstrip("/") == "/dict/test-nl.zip":
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Length", str(len(DICTIONARY)))
            self.end_headers()
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_PUT(self):
        if self.path.rstrip("/") != "/kosync/syncs/progress":
            return self.send(404)
        if not self.kosync_authorized():
            return self.send(401, json.dumps({"message": "Unauthorized"}))
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        document = body.get("document")
        if not document:
            return self.send(400, json.dumps({"message": "document ontbreekt"}))
        timestamp = int(time.time())
        PROGRESS[document] = {
            "percentage": body.get("percentage"),
            "progress": body.get("progress"),
            "device": body.get("device"),
            "device_id": body.get("device_id"),
            "timestamp": timestamp,
        }
        return self.send(200, json.dumps({"document": document, "timestamp": timestamp}))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("Lingering-testserver op http://127.0.0.1:%d" % args.port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
