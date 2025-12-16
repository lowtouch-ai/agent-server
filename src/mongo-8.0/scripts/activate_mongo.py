import subprocess
import gzip
import os.path
import pymongo
from os import popen
import yaml
import logging
from collections import defaultdict

conn_user = os.environ['DB_USER_ADMIN']
conn_pwd = os.environ['DB_USER_ADMIN_PASSWORD']

def userfunc(setup_file):

    with open(setup_file, 'r') as f:
        words = yaml.load(f, Loader=yaml.FullLoader)
        myclient = pymongo.MongoClient(username=conn_user, password=conn_pwd)

    user_pass_map = {}
    if 'users' in words:
       for u in words["users"]:
           username = u['name']
           passwd = u['password']
           string = (passwd[1:])
           passwd = os.environ[string]
           user_pass_map[username] = passwd
           tester = { "name": "test", "use": "test" }

       user_data = defaultdict(dict)
       if 'acl' in words:
           acl = words['acl']
           for entry in acl:
               dbname = entry['database']
               dbuser = entry['user']
               access = entry['access']

               user_data[dbuser][dbname] = access.split(',')
           for user, passw in user_pass_map.items():

               try:

                   role_list = []
                   for i, j in user_data[user].items():
                       for k in j:

                           mydb = myclient[i]
                           mycol = mydb["deleteme"]
                           x = mycol.insert_one(tester)
                           mydb.command('createUser', user, pwd=passw,
                                   roles = [{'role': k.strip(), 'db': i}]
                                   )



               except Exception as e:
                   logging.warning(e)
                   logging.warning("As user {} already exists, updating roles for that user if any ".format(user))
                   mydb.command('updateUser', user, pwd=passw,
                               roles = [{'role': k.strip(), 'db': i} for i, j in user_data[user].items() for k in j] )
       else:
           logging.warning("No acl found from yaml")

    else:
        logging.warning('no users found from yaml')
def main():
    logging.basicConfig(level=logging.INFO,
                        format='%(levelname)s %(message)s')
    setup_file = "/appz/scripts/mongo_contents/setup.yaml"
    userfunc(setup_file)
if __name__ == '__main__':
    main()

