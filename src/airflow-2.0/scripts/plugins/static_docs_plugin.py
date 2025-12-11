from airflow.plugins_manager import AirflowPlugin
from flask import Blueprint, send_from_directory, abort, redirect, url_for, request 
from airflow.www.app import csrf
from flask_login import current_user
import os

STATIC_DOCS_PATH = '/appz/home/airflow/docs'

docs_blueprint = Blueprint(
    'docs_blueprint',
    __name__,
    url_prefix='/docs'
)

csrf.exempt(docs_blueprint)

@docs_blueprint.before_request
def require_auth():
    """Redirect to login if not authenticated"""
    if not current_user.is_authenticated:
        login_url = url_for('Airflow.index', next=request.full_path) 
        return redirect(login_url)
    return None

@docs_blueprint.route('/<path:filename>')
def serve_static(filename):
    full_path = os.path.join(STATIC_DOCS_PATH, filename)
    if not os.path.exists(full_path):
        abort(404, f"File not found: {filename}")
    return send_from_directory(STATIC_DOCS_PATH, filename)

@docs_blueprint.route('/<path:subdir>/<path:filename>')
def serve_static_subdir(subdir, filename):
    full_path = os.path.join(STATIC_DOCS_PATH, subdir, filename)
    if not os.path.exists(full_path):
        abort(404, f"File not found: {subdir}/{filename}")
    return send_from_directory(os.path.join(STATIC_DOCS_PATH, subdir), filename)

class StaticDocsPlugin(AirflowPlugin):
    name = "static_docs_plugin"
    flask_blueprints = [docs_blueprint]