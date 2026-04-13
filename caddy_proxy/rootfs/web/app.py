from flask import Flask, render_template, request, jsonify
import os
import json
import subprocess
import re
import tempfile

from pathlib import Path

app = Flask(__name__, static_folder='static', static_url_path='/static')

# -----------------------------------------------------------------------------
# ПУТИ
# -----------------------------------------------------------------------------
CONFIG_BASE = "/config"
META_DIR = os.path.join(CONFIG_BASE, "meta")
SITES_DIR = os.path.join(CONFIG_BASE, "sites")

# -----------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# -----------------------------------------------------------------------------

def ensure_dirs():
    """Создаёт папки если их нет"""
    os.makedirs(META_DIR, exist_ok=True)
    os.makedirs(SITES_DIR, exist_ok=True)

def get_next_id():
    """Возвращает следующий доступный ID"""
    ensure_dirs()
    max_id = 0
    for f in os.listdir(META_DIR):
        if f.endswith('.json'):
            try:
                id_num = int(f.replace('.json', ''))
                if id_num > max_id:
                    max_id = id_num
            except:
                pass
    return max_id + 1

def get_all_sites():
    """Возвращает список всех сайтов из meta/"""
    ensure_dirs()
    sites = []
    for f in os.listdir(META_DIR):
        if f.endswith('.json'):
            try:
                with open(os.path.join(META_DIR, f), 'r') as fp:
                    site = json.load(fp)
                    sites.append(site)
            except:
                pass
    return sorted(sites, key=lambda x: x.get('id', 0))

def get_site_by_id(site_id):
    """Возвращает сайт по ID"""
    meta_path = os.path.join(META_DIR, f"{site_id}.json")
    if not os.path.exists(meta_path):
        return None
    with open(meta_path, 'r') as fp:
        return json.load(fp)

def save_meta(site_id, data):
    """Сохраняет метаданные в meta/{id}.json"""
    ensure_dirs()
    data['id'] = site_id
    with open(os.path.join(META_DIR, f"{site_id}.json"), 'w') as fp:
        json.dump(data, fp, indent=2)

def delete_meta(site_id):
    """Удаляет метаданные"""
    meta_path = os.path.join(META_DIR, f"{site_id}.json")
    if os.path.exists(meta_path):
        os.remove(meta_path)

def generate_caddy_config(data):
    """Генерирует Caddyfile конфиг

    Сценарии:
    1. force_https = false, scheme = http  -> HTTP → HTTP
    2. force_https = false, scheme = https -> HTTP → HTTPS
    3. force_https = true,  scheme = http  -> HTTPS → HTTP
    4. force_https = true,  scheme = https -> HTTPS → HTTPS
    """

    lines = []

    domain = data['domain']
    scheme = data.get('scheme', 'http')
    upstream_ip = data.get('upstream_ip', '127.0.0.1')
    upstream_port = data.get('upstream_port', 80)
    force_https = data.get('force_https', True)


    # ВХОД (HTTP или HTTPS)
    if force_https:
        lines.append(f"{domain} {{")
    else:
        lines.append(f"http://{domain} {{")


    # БАЗОВЫЕ ЗАГОЛОВКИ
    lines.append("    # Security headers")
    lines.append("    header {")
    lines.append('        X-Frame-Options "SAMEORIGIN"')
    lines.append('        X-Content-Type-Options "nosniff"')
    lines.append('        Referrer-Policy "strict-origin-when-cross-origin"')
    lines.append('        Permissions-Policy "geolocation=(self), payment=(), usb=(self), autoplay=(self), camera=(self), microphone=(self), fullscreen=(self)"')
    lines.append('        -Server')

    csp = normalize_csp(data.get('csp', ''))

    if csp:
        lines.append(f'        Content-Security-Policy "{csp}"')

    lines.append("    }")
    lines.append("")

    # TLS (если включён HTTPS)
    if force_https:
        certfile = data.get('certfile', 'fullchain.pem') or 'fullchain.pem'
        keyfile = data.get('keyfile', 'privkey.pem') or 'privkey.pem'

        lines.append("    # TLS")
        lines.append(f"    tls /ssl/{certfile} /ssl/{keyfile}")
        lines.append("")

        # HSTS (только если включён)
        if data.get('hsts', False):
            hsts_value = "max-age=31536000"
            if data.get('hsts_subdomains', False):
                hsts_value += "; includeSubDomains"

            lines.append("    # HSTS")
            lines.append(f'    header Strict-Transport-Security "{hsts_value}"')
            lines.append("")

    # REVERSE PROXY
    lines.append("    # Reverse proxy")

    # очистка если пользователь вставил nginx-формат
    if "Content-Security-Policy" in csp:
        csp = csp.split("Content-Security-Policy")[-1].strip()
        csp = csp.strip('" ')

    if scheme == 'https':
        lines.append(f"    reverse_proxy https://{upstream_ip}:{upstream_port} {{")
        lines.append("        transport http {")
        lines.append("            tls_insecure_skip_verify")
        lines.append("        }")
        lines.append("        header_up X-Forwarded-Proto {scheme}")

        if csp:
            lines.append("        header_down -Content-Security-Policy")
            lines.append(f'        header_down Content-Security-Policy "{csp}"')

        lines.append("    }")
    else:
        lines.append(f"    reverse_proxy {upstream_ip}:{upstream_port} {{")

        if csp:
            lines.append("        header_down -Content-Security-Policy")
            lines.append(f'        header_down Content-Security-Policy "{csp}"')

        lines.append("    }")

    lines.append("")


    # ADVANCED (пользовательские директивы)
    advanced = remove_csp_from_advanced(data.get('advanced', ''))
    if advanced and advanced.strip():
        lines.append("    # Custom directives")
        for line in advanced.strip().split('\n'):
            lines.append(f"    {line}")
        lines.append("")


    # ЗАКРЫТИЕ
    lines.append("}")

    return '\n'.join(lines)

def generate_stream_config(data):
    """генерации L4"""

    lines = []

    l4 = data.get('l4', [])
    if not l4:
        return ""

    for item in l4:
        port = item.get('port')
        protocol = item.get('protocol', 'tcp')
        upstream_ip = item.get('upstream_ip')
        upstream_port = item.get('upstream_port')

        if not port or not upstream_ip or not upstream_port:
            continue

        if protocol == 'udp':
            listen = f":{port}/udp"
        else:
            listen = f":{port}"

        lines.append(f"{listen} {{")
        lines.append("    route {")
        lines.append("        proxy {")
        lines.append(f"            upstream {upstream_ip}:{upstream_port}")
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        lines.append("")

    return "\n".join(lines)


def normalize_csp(csp: str) -> str:
    if not csp:
        return ""

    # убираем nginx/caddy префиксы
    if "Content-Security-Policy" in csp:
        csp = csp.split("Content-Security-Policy")[-1]

    # убираем header/add_header
    csp = csp.replace("header", "")
    csp = csp.replace("add_header", "")

    # убираем кавычки по краям
    csp = csp.strip().strip('"').strip("'")

    # убираем переносы строк
    csp = csp.replace("\n", " ").replace("\r", " ")

    # схлопываем пробелы
    csp = " ".join(csp.split())

    return csp

def remove_csp_from_advanced(advanced: str) -> str:
    if not advanced:
        return ""

    lines = advanced.split('\n')
    cleaned = []

    for line in lines:
        if "Content-Security-Policy" in line:
            continue
        cleaned.append(line)

    return "\n".join(cleaned)

def is_domain_exists(domain, exclude_id=None):
    """Проверяет, существует ли уже такой домен"""
    sites = get_all_sites()
    for site in sites:
        if site['domain'] == domain and site.get('id') != exclude_id:
            return True
    return False

def validate_caddy_config(caddy_content):
    """Проверяет Caddy конфиг через caddy adapt --validate"""
    import tempfile
    import subprocess
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.caddy', delete=False) as f:
        f.write(caddy_content)
        temp_path = f.name
    
    try:
        result = subprocess.run(
            ['caddy', 'adapt', '--config', temp_path, '--adapter', 'caddyfile', '--validate'],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            return True, None
        else:
            return False, result.stderr
    finally:
        os.unlink(temp_path)

def save_caddy_config(site_id, caddy_content):
    """Сохраняет конфиг. Если невалидный — сохраняет как .disabled"""
    ensure_dirs()
    
    caddy_path = os.path.join(SITES_DIR, f"{site_id}.caddy")
    disabled_path = os.path.join(SITES_DIR, f"{site_id}.caddy.disabled")
    
    # Проверяем валидность
    is_valid, error = validate_caddy_config(caddy_content)
    
    # Всегда сохраняем контент в соответствующий файл
    target_path = caddy_path if is_valid else disabled_path
    with open(target_path, 'w') as fp:
        fp.write(caddy_content)
    
    # Удаляем противоположный файл если существует
    if is_valid and os.path.exists(disabled_path):
        os.remove(disabled_path)
    elif not is_valid and os.path.exists(caddy_path):
        os.remove(caddy_path)
    
    if not is_valid:
        print(f"Site {site_id} config invalid: {error}")
        
    return is_valid

def save_stream_config(site_id, stream_content):
    """Сохраняет stream конфиг."""
    stream_path = os.path.join(SITES_DIR, f"{site_id}.caddy.stream")

    # если пусто — удаляем файл
    if not stream_content.strip():
        if os.path.exists(stream_path):
            os.remove(stream_path)
        return

    with open(stream_path, 'w') as f:
        f.write(stream_content)

def delete_caddy_config(site_id):
    """Удаляет конфиг сайта (и обычный, и disabled)"""
    caddy_path = os.path.join(SITES_DIR, f"{site_id}.caddy")
    disabled_path = os.path.join(SITES_DIR, f"{site_id}.caddy.disabled")
    
    if os.path.exists(caddy_path):
        os.remove(caddy_path)
    if os.path.exists(disabled_path):
        os.remove(disabled_path)

    stream_path = os.path.join(SITES_DIR, f"{site_id}.caddy.stream")
    if os.path.exists(stream_path):
        os.remove(stream_path)

def enable_site(site_id, enabled=True):
    """Включает или выключает сайт с проверкой валидности при включении"""
    caddy_path = os.path.join(SITES_DIR, f"{site_id}.caddy")
    disabled_path = os.path.join(SITES_DIR, f"{site_id}.caddy.disabled")
    
    if enabled:
        # При включении — проверяем валидность disabled файла
        if os.path.exists(disabled_path):
            with open(disabled_path, 'r') as fp:
                caddy_content = fp.read()
            
            is_valid, _ = validate_caddy_config(caddy_content)
            
            if is_valid:
                os.rename(disabled_path, caddy_path)
                return True
            else:
                print(f"Site {site_id} cannot be enabled: config is invalid")
                return False
        elif os.path.exists(caddy_path):
            # Уже включён
            return True
        else:
            print(f"Site {site_id} has no config file")
            return False
    else:
        # При выключении — просто переименовываем
        if os.path.exists(caddy_path):
            os.rename(caddy_path, disabled_path)
            return True
    return False

def reload_caddy():
    """Перезагружает Caddy с проверкой конфига"""
    try:
        # Сначала проверяем валидность конфига
        check_result = subprocess.run(
            ['caddy', 'validate', '--config', '/data/Caddyfile'],
            capture_output=True,
            text=True
        )
        
        if check_result.returncode != 0:
            print(f"Caddy config validation failed: {check_result.stderr}")
            return False
        
        # Если валидация прошла, перезагружаем
        result = subprocess.run(
            ['caddy', 'reload', '--config', '/data/Caddyfile'],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print("Caddy reloaded successfully")
            return True
        else:
            print(f"Caddy reload failed: {result.stderr}")
            # Если reload не удался, но конфиг валиден - проблема может быть в отдельных сайтах
            # Отключаем проблемный сайт
            return False
    except Exception as e:
        print(f"Caddy reload error: {e}")
        return False

# -----------------------------------------------------------------------------
# API ЭНДПОИНТЫ
# -----------------------------------------------------------------------------

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/sites', methods=['GET'])
def get_sites():
    """Получить список всех сайтов"""
    sites = get_all_sites()
    return jsonify({'sites': sites})

@app.route('/api/sites', methods=['POST'])
def create_site():
    """Создать новый сайт"""
    data = request.json
    domain = data.get('domain')
    
    # Проверка уникальности
    if is_domain_exists(domain):
        return jsonify({'error': 'Domain already exists'}), 409
    
    site_id = get_next_id()
    
    # Добавляем статус и ID
    data['status'] = 'online'
    data['reason'] = None
    data['id'] = site_id
    
    # Устанавливаем значения по умолчанию, если их нет
    if 'force_https' not in data:
        data['force_https'] = True
    if 'hsts' not in data:
        data['hsts'] = True
    if 'hsts_subdomains' not in data:
        data['hsts_subdomains'] = True
    
    # Сохраняем метаданные
    save_meta(site_id, data)
    
    # Генерируем и сохраняем Caddy конфиг
    caddy_config = generate_caddy_config(data)
    is_valid = save_caddy_config(site_id, caddy_config)

    # Генерируем и сохраняем streem конфиг
    stream_config = generate_stream_config(data)
    save_stream_config(site_id, stream_config)

    # Обновляем статус в метаданных
    site = get_site_by_id(site_id)
    if site:
        if is_valid:
            site['status'] = 'online'
            site['reason'] = None
        else:
            site['status'] = 'offline'
            site['reason'] = 'invalid'
        save_meta(site_id, site)

    # Перезагружаем Caddy
    reload_caddy()

    if not is_valid:
        # Можно вернуть предупреждение, но не ошибку
        return jsonify({'warning': 'Config saved but invalid, site disabled', 'id': site_id}), 201
    
    return jsonify({'id': site_id, 'status': 'ok'})

@app.route('/api/sites/<int:site_id>', methods=['GET'])
def get_site(site_id):
    """Получить сайт по ID"""
    site = get_site_by_id(site_id)
    if site:
        return jsonify(site)
    return jsonify({'error': 'not found'}), 404

@app.route('/api/sites/<int:site_id>', methods=['PUT'])
def update_site(site_id):
    """Обновить сайт"""
    data = request.json
    domain = data.get('domain')
    
    # Проверка уникальности (исключая текущий ID)
    if is_domain_exists(domain, exclude_id=site_id):
        return jsonify({'error': 'Domain already exists'}), 409
    
    data['status'] = 'online'
    data['reason'] = None
    data['id'] = site_id
    
    # Сохраняем метаданные
    save_meta(site_id, data)
    
    # Генерируем и сохраняем Caddy конфиг
    caddy_config = generate_caddy_config(data)
    is_valid = save_caddy_config(site_id, caddy_config)

    # Генерируем и сохраняем streem конфиг
    stream_config = generate_stream_config(data)
    save_stream_config(site_id, stream_config)

    # Обновляем статус в метаданных
    site = get_site_by_id(site_id)
    if site:
        if is_valid:
            site['status'] = 'online'
            site['reason'] = None
        else:
            site['status'] = 'offline'
            site['reason'] = 'invalid'
        save_meta(site_id, site)

    # Перезагружаем Caddy
    reload_caddy()

    if not is_valid:
        # Можно вернуть предупреждение, но не ошибку
        return jsonify({'warning': 'Config saved but invalid, site disabled', 'id': site_id}), 201
    
    return jsonify({'status': 'ok'})

@app.route('/api/sites/<int:site_id>', methods=['DELETE'])
def delete_site(site_id):
    """Удалить сайт"""
    delete_meta(site_id)
    delete_caddy_config(site_id)

    stream_path = os.path.join(SITES_DIR, f"{site_id}.caddy.stream")
    stream_disabled = f"{stream_path}.disabled"

    if os.path.exists(stream_path):
        os.remove(stream_path)

    if os.path.exists(stream_disabled):
        os.remove(stream_disabled)

    reload_caddy()

@app.route('/api/sites/<int:site_id>/toggle', methods=['POST'])
def toggle_site(site_id):
    """Включить/выключить сайт"""
    data = request.json
    enabled = data.get('enabled', False)
    
    # Пытаемся включить/выключить
    success = enable_site(site_id, enabled)
        
    # Управляем L4
    # если конфиг невалидный — отключаем L4
    stream_path = os.path.join(SITES_DIR, f"{site_id}.caddy.stream")
    stream_disabled = f"{stream_path}.disabled"

    if not success:
        if os.path.exists(stream_path):
            os.rename(stream_path, stream_disabled)

    # toggle L4
    if enabled:
        if os.path.exists(stream_disabled):
            os.rename(stream_disabled, stream_path)
    else:
        if os.path.exists(stream_path):
            os.rename(stream_path, stream_disabled)

    if not success and enabled:
        # Не удалось включить из-за невалидности
        return jsonify({'error': 'Cannot enable: config is invalid'}), 400
    
    # Обновляем статус в метаданных
    site = get_site_by_id(site_id)
    if site:
        if enabled and success:
            site['status'] = 'online'
            site['reason'] = None
        else:
            site['status'] = 'offline'
            site['reason'] = 'user'
        save_meta(site_id, site)
    
    # Перезагружаем Caddy
    reload_caddy()
    
    return jsonify({'status': 'ok'})

@app.route('/api/reload', methods=['POST'])
def reload_sites():
    """Перезагрузить Caddy"""
    if reload_caddy():
        return jsonify({'status': 'ok'})
    return jsonify({'error': 'reload failed'}), 500

# -----------------------------------------------------------------------------
# ЗАПУСК
# -----------------------------------------------------------------------------
if __name__ == '__main__':

    import logging
    logging.getLogger('werkzeug').setLevel(logging.ERROR)

    import flask.cli
    flask.cli.show_server_banner = lambda *args, **kwargs: None

    ensure_dirs()

    app.run(host='0.0.0.0', port=5000, use_reloader=False, debug=False)