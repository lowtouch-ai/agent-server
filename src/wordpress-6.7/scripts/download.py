import yaml
import wget
import os
import logging
import zipfile
import shutil
import sys
import pytz
from datetime import datetime
file = '/wp-contents/contents.yaml'

def start():

  file = '/wp-contents/contents.yaml'  
  with open(file,'r') as file:

    words = yaml.load(file, Loader=yaml.FullLoader)

    if 'theme' in words:

        theme = words['theme']

        if not isinstance(theme, list):
            theme = [ theme ]

        for tm in theme:

            ufile = '/downloads/' + tm['name']

            if 'url' in tm:
            
                themes = tm['url']
                wfile = themes.split("/")[-1]
                fname = '/downloads/' + wfile
                if not os.path.exists('/downloads'):
                    logging.warning('/downloads not found')
                if os.path.exists(fname):
                    logging.info('%s %s' % ('file already exists',fname)) 
                else:
                    wget.download(themes,fname)
                    if os.path.exists(fname):
                        logging.info('%s %s' % ('file downloaded successfully',fname))
                    else: 
                        logging.warning('%s %s' % ('failed to wget',fname))
                    with zipfile.ZipFile(fname, 'r') as zip_ref:
                        zip_ref.extractall('/downloads/')
                    if os.path.exists(ufile):
                        logging.info('file unzip successfully')
                    else:
                        logging.warning('%s %s' % ('failed to unzip',ufile))

            else:
                logging.warning('themes url not found from yaml')
                
    else:
        logging.warning('no themes found from yaml')

    if 'plugins' in words:
        plugins = words['plugins']

        for i in plugins:
            wfile = i.split("/")[-1]
            fname = '/downloads/' + wfile
            if os.path.exists(fname):
                logging.info('%s %s ' % ('file already exists',fname))
            else:     
                wget.download(i,fname)
                if os.path.exists(fname):
                    logging.info('%s %s ' % ('file downloaded successfully',fname))
                else:  
                    logging.warning('%s %s' % ('failed to wget',fname))
    else:
        logging.warning('no plugins found from yaml')
def main():
    logging.basicConfig(level=logging.DEBUG,
                    format='%(levelname)s %(message)s')
    logging.info('start downloading ')
    start()
if __name__ == '__main__':
    main()
           
       
