import yaml
import mysql.connector
import logging
from datetime import datetime
import time
import yaml
import os
import sys
import subprocess
import uuid
connuser = os.environ['MYSQL_USER']
connpasswd = os.environ['MYSQL_PASSWORD']
conndb = os.environ['MYSQL_DATABASE']
table_name = os.getenv('MYSQL_TABLE', 'wp_options')
hostport = "3306"
if os.environ['ENABLE_HA'] == 'yes':
   connhost =  'localhost'
else:
  mysqlhost = os.environ['MYSQL_HOST']
  dbhost = mysqlhost.split(":")
  connhost = dbhost[0]
  hostport = dbhost[1]
def convert(name, file_name):
    with open(file_name, 'r') as file:
       read_option_value =  file.read()
       quote_esc_value = read_option_value.replace("'", "''")
       unicode_quote_esc_value = quote_esc_value.replace("u2019","\\\\u2019")
       option_value = unicode_quote_esc_value.replace("/", "\\\/")
       convert_sql ="SET @option_value = '"+option_value+"';\n" + "update wp_options set option_value=JSON_UNQUOTE(@option_value) where  option_name='"+name+"';\n"
       file_sql="/tmp/" + str(uuid.uuid4()) + '.sql'
       txt=open(file_sql,"w+")
       txt.write(convert_sql)
       txt.close()
       logging.info("FILENAME:\t"+file_sql+"\n")
       backup(name, file_sql)
def backup(name, file_sql):
    mydb = mysql.connector.connect(host=connhost, user=connuser, passwd=connpasswd, database=conndb, port=hostport)
    if mydb.is_connected():
        logging.info('MYSQL connected mysql with user:-' + connuser + ' DB:-' + conndb + ' host:-'+ connhost + ' port: '+ hostport)
    else:
        logging.warning('MYSQL failed to connect mysql with user:-' + connuser + ' DB:- ' + conndb + ' host:-' + connhost + ' port: '+ hostport)
    cursor = mydb.cursor(dictionary=True,buffered=True)
    o_name = "gf_stla_grid_layout%"
    sql = "select option_name from " + table_name + " where option_name like '"+o_name+"'"
    try:
        cursor.execute(sql)
        db_list = cursor.fetchall()
    except mysql.connector.Error as err:
        logging.warning(err)
        logging.warning("Error Code:", err.errno)
        logging.warning("SQLSTATE", err.sqlstate)
        logging.warning("Message", err.msg)
        sys.exit()
    if any(d['option_name'] == name for d in db_list):
                    logging.info(name + ' exist in ' + table_name + ',updating current value')
                    wp_query='wp --allow-root db query < ' + file_sql
                    process = subprocess.call(wp_query,shell=True)
                    if process == 0:
                          logging.info('%s' % ('wp option updated'))
                    else:
                          logging.warning('failed to update wp option')
                    os.remove(file_sql)
    else:
            logging.info(name + ' not found in ' + table_name + ',inserting current value')
            intert_command = '%s %s %s' % ('wp --allow-root option update',name,'""')
            process_insert = subprocess.call(intert_command,shell=True)
            if process_insert == 0:
                 logging.info('%s' % ('wp option updated as blank'))
            else:
                 logging.warning('failed to update wp option as blank')
            wp_query='wp --allow-root db query < ' + file_sql
            process = subprocess.call(wp_query,shell=True)
            if process == 0:
                  logging.info('%s' % ('wp option updated'))
            else:
                  logging.warning('failed to update wp option')
            os.remove(file_sql)
    if mydb is not None and mydb.is_connected():
            mydb.close()
def start():
    file = '/wp-contents/contents.yaml'
    with open(file,'r') as file:
        words = yaml.load(file, Loader=yaml.FullLoader)
        if 'options' in words:
             options = words['options']
             for key in options:
                 name = key['name']
                 file_name = '/wp-contents/options/' + key['file']
                 convert(name,file_name)
        else:
           logging.info('options not found from contents.yaml')
def main():
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.DEBUG)
    formatter = logging.Formatter('%(levelname)s %(message)s')
    handler.setFormatter(formatter)
    root.addHandler(handler)
    logging.info('start parsing query')
    start()
if __name__ == '__main__':
    main()
