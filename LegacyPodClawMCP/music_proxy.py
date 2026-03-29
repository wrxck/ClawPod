#!/usr/bin/env python3
"""
LegacyPodClaw Music Proxy - yt-dlp bridge for iPod Touch

Runs on a computer on the same network as the iPod.
Handles YouTube signature deciphering that can't run on iOS 6.

Usage:
    pip3 install yt-dlp
    python3 music_proxy.py [--port 18790] [--host 0.0.0.0]

Then in LegacyPodClaw Settings, set Music Proxy URL to:
    http://YOUR_COMPUTER_IP:18790

API:
    GET /info?v=VIDEO_ID   → JSON: {title, artist, duration, thumbnail}
    GET /audio?v=VIDEO_ID  → Raw M4A audio file
    GET /health            → {"status":"ok"}
"""

import argparse
import json
import os
import subprocess
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

class MusicProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        if path == '/health':
            self._json_response({'status': 'ok'})
            return

        if path == '/info':
            video_id = params.get('v', [None])[0]
            if not video_id:
                self._json_response({'error': 'Missing v parameter'}, 400)
                return
            self._handle_info(video_id)
            return

        if path == '/audio':
            video_id = params.get('v', [None])[0]
            if not video_id:
                self._json_response({'error': 'Missing v parameter'}, 400)
                return
            self._handle_audio(video_id)
            return

        self._json_response({'error': 'Not found'}, 404)

    def _handle_info(self, video_id):
        """Get video metadata via yt-dlp."""
        try:
            url = f'https://www.youtube.com/watch?v={video_id}'
            result = subprocess.run(
                ['yt-dlp', '--dump-json', '--no-download', url],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode != 0:
                self._json_response({'error': f'yt-dlp failed: {result.stderr[:200]}'}, 500)
                return

            data = json.loads(result.stdout)
            info = {
                'title': data.get('title', 'Unknown'),
                'artist': data.get('uploader', data.get('artist', 'Unknown')),
                'duration': data.get('duration', 0),
                'thumbnail': data.get('thumbnail', ''),
                'album': data.get('album', ''),
            }
            # Clean up artist name (remove " - Topic" suffix from YouTube Music)
            artist = info['artist']
            if artist.endswith(' - Topic'):
                artist = artist[:-8]
            info['artist'] = artist

            self._json_response(info)
        except subprocess.TimeoutExpired:
            self._json_response({'error': 'Timeout getting video info'}, 504)
        except Exception as e:
            self._json_response({'error': str(e)}, 500)

    def _handle_audio(self, video_id):
        """Download audio and serve the file."""
        try:
            url = f'https://www.youtube.com/watch?v={video_id}'
            with tempfile.TemporaryDirectory() as tmpdir:
                output_path = os.path.join(tmpdir, 'audio.mp3')
                # Download best audio, then convert to MP3 with ffmpeg
                # iOS 6 Music.app needs: MP3, ID3v2.3, 192kbps CBR, 44.1kHz stereo
                raw_path = os.path.join(tmpdir, 'raw_audio')
                result = subprocess.run(
                    ['yt-dlp',
                     '-f', 'bestaudio',
                     '-o', raw_path,
                     url],
                    capture_output=True, text=True, timeout=120
                )
                # Find downloaded file (yt-dlp adds extension)
                raw_file = None
                for f in os.listdir(tmpdir):
                    if f.startswith('raw_audio'):
                        raw_file = os.path.join(tmpdir, f)
                        break

                if raw_file and os.path.exists(raw_file):
                    # Convert to iOS 6-compatible MP3
                    result = subprocess.run(
                        ['ffmpeg', '-y', '-i', raw_file,
                         '-codec:a', 'libmp3lame',
                         '-b:a', '192k',
                         '-ar', '44100',
                         '-ac', '2',
                         '-id3v2_version', '3',
                         '-write_id3v1', '1',
                         output_path],
                        capture_output=True, text=True, timeout=120
                    )
                elif result.returncode != 0:
                    # Fallback: let yt-dlp handle conversion
                    result = subprocess.run(
                        ['yt-dlp',
                         '--extract-audio',
                         '--audio-format', 'mp3',
                         '--audio-quality', '192K',
                         '-o', output_path,
                         url],
                        capture_output=True, text=True, timeout=120
                    )

                if not os.path.exists(output_path):
                    self._json_response({'error': f'Download failed: {result.stderr[:200]}'}, 500)
                    return

                file_size = os.path.getsize(output_path)
                self.send_response(200)
                self.send_header('Content-Type', 'audio/mpeg')
                self.send_header('Content-Length', str(file_size))
                self.end_headers()

                with open(output_path, 'rb') as f:
                    while True:
                        chunk = f.read(65536)
                        if not chunk:
                            break
                        self.wfile.write(chunk)

        except subprocess.TimeoutExpired:
            self._json_response({'error': 'Timeout downloading audio'}, 504)
        except Exception as e:
            self._json_response({'error': str(e)}, 500)

    def _json_response(self, data, status=200):
        body = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        print(f'[MusicProxy] {args[0]}')

def main():
    parser = argparse.ArgumentParser(description='LegacyPodClaw Music Proxy')
    parser.add_argument('--host', default='0.0.0.0', help='Bind address')
    parser.add_argument('--port', type=int, default=18790, help='Port number')
    args = parser.parse_args()

    # Check yt-dlp is available
    try:
        result = subprocess.run(['yt-dlp', '--version'], capture_output=True, text=True)
        print(f'[MusicProxy] yt-dlp version: {result.stdout.strip()}')
    except FileNotFoundError:
        print('[MusicProxy] ERROR: yt-dlp not found. Install with: pip3 install yt-dlp')
        return

    server = HTTPServer((args.host, args.port), MusicProxyHandler)
    print(f'[MusicProxy] Listening on {args.host}:{args.port}')
    print(f'[MusicProxy] Set Music Proxy URL in LegacyPodClaw Settings to: http://YOUR_IP:{args.port}')
    server.serve_forever()

if __name__ == '__main__':
    main()
