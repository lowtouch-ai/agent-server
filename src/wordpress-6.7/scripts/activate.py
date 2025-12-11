import yaml
import os
import shutil
import sys
import subprocess
import logging
import pytz
from datetime import datetime

def start():

  file = '/wp-contents/contents.yaml'

  with open(file,'r') as file:

    words = yaml.load(file, Loader=yaml.FullLoader) 

    if 'theme' in words:
        
        theme = words['theme']

        if not isinstance(theme, list):
            theme = [ theme ]

        for tm in theme:

            if 'url' in tm:
                themes = tm['url']
                wfile = themes.split("/")[-1]
                fname = '/downloads/' + wfile  
            else:
                logging.warning('themes url not found from yaml')

            if not os.path.exists('/downloads'):
                logging.warning('/downloads folder not found')

            ufile = tm['name']
            theme_file = '/downloads/'+ufile 

            if os.path.exists(theme_file):         
                shutil.move(theme_file, '/var/www/html/wp-content/themes') 
                if os.path.exists(theme_file):
                    logging.warning('%s %s' % ('failed to move the file',theme_file))
                else:
                    logging.info('%s %s' % (theme_file,'moved successfully'))              

            try:

                command='wp --allow-root theme activate ' + ufile 
                logging.info(command)
                process = subprocess.call(command,shell=True)
                if process == 0:
                    logging.info('theme activated')
                else:
                    logging.warning('theme not activated') 

            except Exception as e:

                logging.warning('%s %s' % ('fun_start', str(e)))
                logging.warning('%s' % ('failed to active'))

    else:
        logging.warning('themes not found from yaml')
    
    try:

        if 'plugins' in words:
            plugins = words['plugins']
            for i in plugins:
                wfile = i.split("/")[-1]
                fname = '/downloads/' + wfile
                command='wp --allow-root plugin install ' + fname + ' --activate'
                logging.info(command)
                process = subprocess.call(command, shell=True)
                if process == 0:
                    logging.info('%s' % ('plugin activated'))
                else:
                    logging.warning('plugin not activated')
        else:
            logging.warning('plugins not found from yaml')

    except Exception as e:
        logging.warning('%s %s' % ('fun_start', str(e)))
                
    try:

        if 'gforms' in words:
            form = words['gforms']
            form_path = '/wp-contents/forms/'
            for key in form:
                command='wp --allow-root gf form update ' + str(key['id']) + ' --file=' + form_path + key['name']
                logging.info(command)
                process = subprocess.call(command, shell=True)
                if process == 0:
                    logging.info('%s' % ('form activated'))
                else:
                    logging.warning('%s %s' % (key['name'],'form not activated')) 

    except Exception as e:
        logging.warning('%s %s' % ('fun_start', str(e)))
    
def main():
    logging.basicConfig(level=logging.DEBUG,
                    format='%(levelname)s %(message)s')
    logging.info('start downloading ')
    start()

if __name__ == '__main__':
    main()

