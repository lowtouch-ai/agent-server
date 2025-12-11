import yaml
import requests
import time
import os
import logging
import zipfile
from requests.auth import HTTPBasicAuth
import mysql.connector
import sys
import pymysql
import pwd
import os.path
from os import path
from os import popen
from subprocess import PIPE,Popen
from datetime import datetime
from mysql.connector import Error

conn_user = os.environ['MYSQL_CONNECTUSER']
conn_db = os.environ['MYSQL_CONNECTIONDB']
conn_pass = os.environ['MYSQL_ROOT_PASSWORD']

def createuser():
    userconn = mysql.connector.connect(host='localhost', database=conn_db, user=conn_user, password=conn_pass)
    cursor1 = userconn.cursor()
    return cursor1, userconn
def createdb():
    dbconn = pymysql.connect(host='localhost', database=conn_db, user=conn_user, password=conn_pass)
    cursor2 = dbconn.cursor()
    return cursor2, dbconn

def user(setup_file):
    cursor1,userconn = createuser()
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        cursor1.execute("SELECT user FROM mysql.user;")
        list_users = cursor1.fetchall();
        if 'users' in words:
            users = words['users']
            for user in users:
                username = user['name']
                passwd = user['password']
                string = (passwd[1:])
                passwd = os.environ[string]
                if (username,) in list_users:
                    logging.warning("User '{}' already exists".format(username))
                else:
                    if username == 'root':
                        sqlCreateUser = "CREATE USER '%s'@'localhost' IDENTIFIED BY '%s';"%(username, passwd);
                    else:
                        sqlCreateUser = '%s "%s" %s"%s" %s "%s" %s' %('CREATE USER',username,'@','%','IDENTIFIED BY',passwd,';')
                    cursor1.execute(sqlCreateUser)
                    logging.info("User '{}' created".format(username))
        else:
            logging.warning('no users found from yaml')
    cursor1.close()
    userconn.close()

def db(setup_file):
    cursor2,dbconn = createdb()
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        cursor2.execute("SHOW DATABASES;")
        list_db = cursor2.fetchall();
        if 'databases' in words:
            databases = words['databases']
            for db in databases:
                dbname = db['name']
                if (dbname,) in list_db:
                    logging.warning("Database '{}' already exists" .format(dbname))
                else:
                    sqlCreateDb = "CREATE DATABASE "+dbname+";"
                    cursor2.execute(sqlCreateDb)
                    logging.info("Database '{}' created" .format(dbname))
        else:
            logging.warning("No database found from yaml")
        if 'acl' in words:
            acl = words['acl']
            for a in acl:
                dbname = a['database']
                owner = a['user']
                privilege = a['access']
                cursor2.execute("SHOW DATABASES;")
                list_db = cursor2.fetchall();
                if (dbname,) in list_db:

                    sqlGrantPrivileges = "GRANT "+privilege+" ON "+dbname+".* TO '"+owner+"'@'%';"
                    logging.info("Granted privilegs to the owner '{}' on database '{}'" .format(owner,dbname))
                    cursor2.execute(sqlGrantPrivileges)
                    sqlFlushPrivileges = "FLUSH PRIVILEGES;"
                    cursor2.execute(sqlFlushPrivileges)
                    logging.info("User '{}' has been updated with privileges on the database '{}'" .format(owner,dbname))
        else:
            logging.warning("No acl found from yaml")
    cursor2.close()
    dbconn.close()

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

            else:
                logging.info("'{}' Invalid dump file format" .format(f_name))

def restore_db(setup_file,dump_file,dbname):
    cursor2,dbconn = createdb()
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        cursor2.execute("SHOW DATABASES;")
        list_db = cursor2.fetchall()
        if 'restore' in words:
            restore = words['restore']
            for r in restore:
                dbname = r['database']

                rToken = restoretoken(setup_file)
                dump_file = download_bkp_url(setup_file)
                df_namecheck = dump_file.split('/')[-1].split('.')[0]

                if rToken is not None:
                    logging.info("Valid .sql file found for the given database")
                    if (dbname,) in list_db:

                        logging.warning("'{}' Database already exists".format(dbname))
                    else:
                        logging.warning("'{}' Couldn't find the database".format(dbname))
                        sqlCreateDb = "CREATE DATABASE "+dbname+";"
                        cursor2.execute(sqlCreateDb)
                        logging.info("'{}' Database created".format(dbname))
                    command = 'mysql -u '+conn_user+' -p'+conn_pass+' '+dbname+' < '+dump_file+''
                    proc = Popen(command,shell=True)
                    proc.wait()
                    logging.info("{} has been restored to the database {}" .format(dump_file,dbname))
                else:
                    logging.warning("Error encountered on receiving rToken")
                    sys.exit()

def restore_db_file(setup_file,bkp_file,dbname):
    cursor2,dbconn = createdb()
    with open(setup_file,'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        cursor2.execute("SHOW DATABASES;")
        list_db = cursor2.fetchall()
        if 'restore' in words:
            restore = words['restore']
            for r in restore:
                dbname = r['database']

                rToken = restoretoken(setup_file)
                dump_file = bkp_file
                #df_namecheck = dump_file.split('/')[-1].split('.')[0]

                if rToken is not None:
                    logging.info("Valid .sql file found for the given database")
                    if (dbname,) in list_db:

                        logging.warning("'{}' Database already exists".format(dbname))
                    else:
                        logging.warning("'{}' Couldn't find the database".format(dbname))
                        sqlCreateDb = "CREATE DATABASE "+dbname+";"
                        cursor2.execute(sqlCreateDb)
                        logging.info("'{}' Database created".format(dbname))
                    dump_file_path = '/appz/scripts/mariadb-contents/'+dump_file+''
                    command = 'mysql -u '+conn_user+' -p'+conn_pass+' '+dbname+' < '+dump_file_path+''
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
                            source = n['source']
                            if 'file' in source:
                                bkp_file = source['file']
                                restore_db_file(setup_file,bkp_file,dbname)
                            if 'url' in source:
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
    setup_file = "/appz/scripts/mariadb-contents/setup.yaml"
    user(setup_file)
    db(setup_file)
    trigger(setup_file)

if __name__ == '__main__':
    main()

