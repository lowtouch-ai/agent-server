#!/usr/bin/python3
import time
from urllib.parse import parse_qs
from html import escape
import os
import random
import string
import subprocess
import logging

logging.basicConfig(level=logging.DEBUG, format='%(levelname)s %(message)s')

def get_random_password(length):
    password_characters = string.ascii_letters + string.digits
    return ''.join(random.choice(password_characters) for _ in range(length))

def application(environ, start_response):
    try:
        request_body_size = int(environ.get('CONTENT_LENGTH', 0))
    except ValueError:
        status = '411 Length Required'
        code = "Content-Length header is missing or invalid.\n"
        response_header = [('Content-type', 'text/html')]
        start_response(status, response_header)
        return [code.encode('utf-8')]

    request_body = environ['wsgi.input'].read(request_body_size)

    if os.getenv('ENABLE_AUTO_PASSWORD', 'False').lower() == 'false':
        status = '404 Not Found'
        code = "404 Not Found: ENABLE_AUTO_PASSWORD is disabled\n"
        response_header = [('Content-type', 'text/html')]
        start_response(status, response_header)
        return [code.encode('utf-8')]

    try:
        o = request_body.decode('utf-8')
        if ":" not in o:
            status = '400 Bad Request'
            code = "Invalid request format. Expected 'app:env'\n"
            response_header = [('Content-type', 'text/html')]
            start_response(status, response_header)
            return [code.encode('utf-8')]

        full = o.split(":")
        app, env = full[0], full[1]

        if not app:
            status = '400 Bad Request'
            code = "APP_ROLE is missing.\n"
            logging.error('ERROR APP_ROLE not found from env')
        elif not env:
            status = '400 Bad Request'
            code = "KEY is missing.\n"
            logging.error('ERROR KEY not found from env')
        else:
            Rvalue = get_random_password(20)
            if not Rvalue:
                status = '500 Internal Server Error'
                code = "Failed to generate random password.\n"
                logging.error('ERROR Rvalue not generated')
            else:
                os.putenv("KEY", str(env))
                os.putenv("PASS", str(Rvalue))
                os.putenv("APPROLE", str(app))

                command = 'sudo -E bash appz/scripts/vault-provision.sh'
                logging.info("Adding secret in vault ...")
                process = subprocess.run(command, shell=True)

                if process.returncode == 0:
                    status = '200 OK'
                    code = "Password successfully generated.\n"
                    logging.info("vault-provision.sh script successfully generated the password.")
                else:
                    status = '500 Internal Server Error'
                    code = f"Failed to run vault-provision.sh script. Return code: {process.returncode}. Check the logs.\n"
                    logging.error(f"vault-provision.sh failed with return code: {process.returncode}")

    except Exception as e:
        status = '500 Internal Server Error'
        code = f"Internal Server Error: {str(e)}\n"
        logging.warning(f"Oops! {e} occurred.")

    response_header = [('Content-type', 'text/html')]
    start_response(status, response_header)
    return [code.encode('utf-8')]
