"""Interactive setup. Credentials are kept outside the Flutter project."""
import getpass
import json
import os
import secrets
import sys
from pathlib import Path

def config_dir():
    root = Path(os.environ.get('LOCALAPPDATA', str(Path.home() / '.config')))
    return root / 'LedgerArcLocalAI'

def save_config(name, data):
    directory = config_dir()
    directory.mkdir(parents=True, exist_ok=True)
    if os.name != 'nt':
        directory.chmod(0o700)
    target = directory / name
    temp = directory / (name + '.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
    temp.replace(target)

def main():
    from server import ApiError, list_models
    print('LedgerArc yerel AI bağlantı ayarı')
    print('Anahtar yalnızca bu bilgisayarda, Windows kullanıcı ayarları altında tutulur.')
    key = getpass.getpass('Gemini API anahtarını yapıştırın (görünmez) ve Enter: ').strip()
    if not key:
        raise SystemExit('Anahtar girilmedi.')
    try:
        models = list_models(key)
    except ApiError as error:
        raise SystemExit(f'{error.code}: {error.message}') from None
    if not models:
        raise SystemExit('Bu anahtarla içerik üreten model listelenemedi.')
    for index, name in enumerate(models, 1):
        print(f'{index}. {name}')
    print('Metin + görsel/PDF destekleyen bir Flash modeli seçin.')
    print('Listelenmesi tek başına görsel veya ses desteğini garanti etmez; test edeceğiz.')
    try:
        selected = int(input('Modelin sıra numarası: '))
        if not 1 <= selected <= len(models):
            raise ValueError()
    except ValueError:
        raise SystemExit('Geçerli bir sıra numarası girin; ayarlar değiştirilmedi.') from None
    token = secrets.token_urlsafe(32)
    save_config('server.json', {'api_key': key, 'model': models[selected - 1], 'local_token': token})
    save_config('client.json', {'LEDGERARC_LOCAL_TOKEN': token})
    print('Ayarlar kaydedildi. Önce 2-SERVISI-BASLAT.cmd, sonra 3-UYGULAMAYI-BASLAT.cmd açın.')

if __name__ == '__main__':
    if sys.version_info < (3, 10):
        raise SystemExit('Python 3.10 veya üzeri gerekli.')
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        raise SystemExit('Kurulum iptal edildi.')
