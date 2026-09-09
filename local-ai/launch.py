"""Launch Flutter without putting the provider key in compiler arguments."""
import shutil
import subprocess
from pathlib import Path
from setup import config_dir

project = Path(__file__).resolve().parent.parent
settings = config_dir() / 'client.json'
if not (project / 'pubspec.yaml').exists():
    raise SystemExit('local-ai klasörünü pubspec.yaml dosyasının yanına kopyalayın.')
if not settings.exists():
    raise SystemExit('Önce 1-AYARLA.cmd çalıştırın.')
flutter = shutil.which('flutter')
if not flutter:
    raise SystemExit('Flutter bulunamadı. VS Code terminalinden flutter --version komutunu kontrol edin.')
raise SystemExit(subprocess.call([flutter, 'run', '-d', 'windows',
                                 '--dart-define-from-file=' + str(settings)], cwd=project))
