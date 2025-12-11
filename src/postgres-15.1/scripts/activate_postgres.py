import yaml
import re
import requests
import wget
import os
import logging
import zipfile
from requests.auth import HTTPBasicAuth
import shutil
import sys
import pytz
import time
import psycopg2
import pwd
import subprocess
import gzip
import os.path
from os import path
from subprocess import PIPE,Popen
from zipfile import ZipFile
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from datetime import datetime


connuser = os.environ['POSTGRESQL_CONNECTUSER']
conndb = os.environ['POSTGRESQL_CONNECTIONDB']
connport = os.environ['POSTGRESQL_PORT']

def basic():
    conn1 = psycopg2.connect(host="localhost", port = connport, database= conndb, user=connuser)
    conn1.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT);
    cursor1 = conn1.cursor()
    return cursor1, conn1
def new(dbname):
    conn2 = psycopg2.connect(host="localhost", port = connport, database="%s" % (dbname,), user=connuser)
    conn2.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT);
    cursor2 = conn2.cursor()
    return cursor2, conn2
def obj(setup_file):
    cursor1,conn1 = basic()
    with open(setup_file,'r') as file:
        words = yaml.load(file, Loader=yaml.FullLoader)
        cursor1.execute("SELECT usename FROM pg_shadow;")
        list_users = cursor1.fetchall()
        cursor1.execute("SELECT spcname FROM pg_tablespace;")
        list_spc = cursor1.fetchall()
        cursor1.execute("SELECT datname FROM pg_database;")
        list_db = cursor1.fetchall()
        if 'users' in words:
            users = words['users']
            for user in users:
                username = user['name']
                pswd = user['password']
                string = (pswd[1:])
                password = os.environ[string]
                role = user['role'].split(",")
                if (username,) in list_users:
                    logging.warning("'{}'User already exists".format(username))
                else:
                    psqlCreateUser = "create user "+username+" with encrypted password '"+password+"';"
                    cursor1.execute(psqlCreateUser)
                    logging.info("'{}'User created and updated user role to Superuser".format(username))
                    for x in role:
                        userPermission = "alter user "+username+" with "+x+";"
                        cursor1.execute(userPermission)
        else:
            logging.warning('no users found from yaml')
        if 'databases' in words:
            databases = words['databases']
            for db in databases:
                dbname = db['name']
                owner = db['owner']
                tablespace = db['tablespace'][0]
                ts_name = tablespace['name']
                location = tablespace['location']
                if os.path.exists(location):
                    logging.warning("'{}'Tablespace location already exist".format(location))
                else:
                    os.makedirs(location)
                    uid, gid =  pwd.getpwnam('postgres').pw_uid, pwd.getpwnam('postgres').pw_uid
                    os.chown(location, uid, gid)
                    logging.info("'{}'Tablespace location created".format(location))
                    if (ts_name,) in list_spc:
                        logging.warning("'{}' Tablespace already exists".format(ts_name))
                    else:
                        psqlCreateSpc = "CREATE TABLESPACE "+ts_name+" LOCATION '"+location+"';"
                        cursor1.execute(psqlCreateSpc)
                        logging.info("'{}'Tablespace created".format(ts_name))
                        if (dbname,) in list_db:
                            logging.warning("'{}'Database already exists".format(dbname))
                        else:
                            psqlCreateDb = 'CREATE DATABASE "'+dbname+'" OWNER '+owner+' TABLESPACE '+ts_name+';'
                            cursor1.execute(psqlCreateDb)
                            logging.info("'{}'Database created".format(dbname))
        else:
            logging.warning('no databases found from yaml')

    cursor1.close()
    conn1.close()
def schema(setup_file):
    with open(setup_file,'r') as file:
        words = yaml.load(file, Loader=yaml.FullLoader)
        if 'databases' in words:
            databases = words['databases']
            for db in databases:
                dbname = db['name']
                if 'schemas' in db:
                    schema = db['schemas']
                    for s in schema:
                        schema_name = s['name']
                        authorised_user = s['authorised_user']
                        path = s['search_path']
                        cursor2,conn2 = new(dbname)
                        psqlCreateSchema = "CREATE SCHEMA IF NOT EXISTS "+schema_name+" AUTHORIZATION "+authorised_user+";"
                        cursor2.execute(psqlCreateSchema)
                        logging.info("'{}'Schema created".format(schema_name))
                        if path == True:
                            psqlAlterUserSchema = "ALTER USER "+authorised_user+" SET search_path = "+schema_name+";"
                            cursor2.execute(psqlAlterUserSchema)
                            logging.info("'{}'Set-up the schema search path".format(schema_name))
                        else:
                            logging.warning("'{}'schema path set false".format(schema_name))
                    cursor2.close()
                    conn2.close()
                else:
                    logging.warning("'{}'no schemas found from yaml".format(dbname))
        else:
            logging.warning('no databases and schema found from yaml')



def restoretoken(setup_file):
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        if 'restore' in words:
            rtoken = words['restore']
            for r in rtoken :
                rtoken = r['token']
        return rtoken


def usercheck(setup_file):
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        if 'restore' in words:
            users = words['restore']
            for r in  users:
                source = r['source']
                if 'user' not in source:
                    logging.warning("No username found")
                    user = None
                else:
                    user = source['user']
        return user

def password(setup_file):
    with open(setup_file,'r') as f:
        words =  yaml.load(f, Loader=yaml.FullLoader)
        if 'restore' in words:
            paswd = words['restore']
            for p in paswd:
                source = p['source']
                if 'password' not in source:
                    logging.warning("No password found for the username")
                    passwd = None
                else:
                    pswd = source['password']
                    string = (pswd[1:])
                    passwd = os.environ[string]
        return passwd

def get_url(setup_file):
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        if 'restore' in words :
            bkp_url = words['restore']
            for bkp in bkp_url:
                source = bkp['source']
                if 'url' not in source:
                    logging.info("Backup URL not Found")
                else:
                    url = source['url']
                    logging.info("'{}' Found backup URL".format(url))
        return url

def download_bkp_url(setup_file):
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        url = get_url(setup_file)
        user = usercheck(setup_file)
        passwd = password(setup_file)
        if user is None or passwd is None:
            logging.warning("No username/password supplied, Trying to download backup URL without credentials")
            r = requests.get(url, verify=False)
            status = r.status_code
        else:
            logging.info("Downloading backup URL with username/password")
            r = requests.get(url, auth=HTTPBasicAuth(user, passwd), verify=False)
            status = r.status_code
        if (status != 200):
            logging.warning("Status code invalid: %s" % (status))
        else:
            chunk_size=128
            u_name = url.rsplit('/',1)[1]
            f_name = '/tmp/'+u_name+''
            destination = '/appz/data/'
            if u_name.endswith(".zip") == True:
                with open(f_name, 'wb') as fd:
                    for chunk in r.iter_content(chunk_size=chunk_size):
                        fd.write(chunk)
                with zipfile.ZipFile(f_name, 'r') as z:
                    z.extractall(destination)
                    logging.info("Contents extracted to the destination '{}'" .format(destination))
                    df = z.namelist()[0]
                    dump_file = destination + df
                    os.remove(f_name)
                    logging.info("Removed uploaded backup zipfile '{}'" .format(f_name))
                    if path.exists(dump_file):
                        logging.info("'{}' File downloaded successfully".format(dump_file))
                        return dump_file
                    else:
                        logging.info("'{}' File not downloaded, some errors encountered" .format(dump_file))
            elif u_name.endswith(".sql") == True:
                with open(f_name, 'wb') as fd:
                    for chunk in r.iter_content(chunk_size=chunk_size):
                        fd.write(chunk)
                dump_file = f_name
                return dump_file
            else:
                logging.info("'{}' Invalid dump file format" .format(f_name))

def restore_db(setup_file,dump_file,dbname):
    cursor1, conn1 = basic()
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        cursor1.execute("SELECT datname FROM pg_database;")
        list_db = cursor1.fetchall()
        if 'restore' in words:
            restore = words['restore']
            for r in restore:
                pg_db = r['database']
                pg_user = r['user']

                rToken = restoretoken(setup_file)
                dump_file = download_bkp_url(setup_file)
                df_namecheck = dump_file.split('/')[-1].split('.')[0]

                if rToken is not None:
                    logging.info("Valid .sql file found for the given database")
                    if (dbname,) in list_db:

                        logging.warning("'{}' Database already exists".format(dbname))
                    else:
                        logging.warning("'{}' Couldn't find the database".format(dbname))
                        psqlCreateDb = 'CREATE DATABASE "'+dbname+'";'
                        cursor1.execute(psqlCreateDb)
                        logging.info("'{}' Database created".format(dbname))
                    command = 'psql -U '+pg_user+' '+pg_db+' < '+dump_file+''
                    proc = Popen(command,shell=True)
                    proc.wait()
                    logging.info("{} has been restored to the database {}" .format(dump_file,dbname))
                else:
                    logging.warning("Error encountered on receiving rToken")
                    sys.exit()

def trigger(setup_file):
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        if 'restore' in words:
            name = words['restore']
            for n in name :
                dbname = n['database']
                rToken = restoretoken(setup_file)
                date_time_restore = rToken
                logging.info("restore token '{}' found. Initiating restore token validation" .format(rToken))
                if date_time_restore is not None:
                    pattern = '%Y%m%d-%H%M'
                    epoch = int(time.mktime(time.strptime(date_time_restore,pattern)))
                    current_time = int(time.time())
                    if current_time < epoch :
                        diff = epoch - current_time
                        if diff < 900:
                            logging.info("DB_RESTORE_TOKEN validated. Initiating DB backup restore")
                            dump_file = download_bkp_url(setup_file)
                            restore_db(setup_file,dump_file,dbname)
                        else:
                            logging.warning("DB_RESTORE_TOKEN not valid! time difference > 15")
                    else:
                        logging.warning("DB_RESTORE_TOKEN not valid! current time > DB_RESTORE_TOKEN window")
                else:
                    logging.warning("DB RESTORE TOKEN not found. No need to proceed database restore")


def main():
    logging.basicConfig(level=logging.DEBUG,
                    format='%(levelname)s %(message)s')
    setup_file = "/appz/scripts/postgres-contents/setup.yaml"
    obj(setup_file)
    schema(setup_file)
    trigger(setup_file)

if __name__ == '__main__':
    main()



