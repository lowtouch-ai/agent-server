import xlrd
import openpyxl
import pandas as pd
import subprocess
import logging
import os
import csv
import sys
import zipfile
import datetime
import urllib.parse
from urllib.parse import urlparse
from os.path import basename
logging.basicConfig(format='%(message)s', level=logging.INFO)
pd.set_option('display.max_colwidth', None)

def cleanup_posts(input_file):
    try:
        df1_input = pd.read_excel(input_file, usecols=[0,1], header=0)
        logging.info('%s' % ('INFO Successfully loaded input xlsx in to dataframe'))
    except Exception as e:
        logging.error('%s %s' % ('ERROR Error in loading input file', str(e)))

    try:
        command_list = 'wp --allow-root post list --post_type=attachment --fields=ID,guid'
        process_list = subprocess.check_output(command_list,shell=True)
        process_list = process_list.decode('utf-8')
    except subprocess.CalledProcessError as e:
        logging.error('%s %s' % ('ERROR Post listing failed', str(e)))

    try:
        sourceFile = open('posts_list.txt', 'w')
        print(process_list, file = sourceFile)
        sourceFile.close()
        df2_target = pd.read_csv("posts_list.txt", delimiter = '\t')
        logging.info('%s' % ('INFO Saved posts list in to dataframe'))
        os.remove('posts_list.txt')
    except Exception as e:
        logging.error('%s %s' % ('ERROR Writing to text file failed', str(e)))

    url_list = []
    for x, y in df2_target.itertuples(index=False):
        df2_target_url = y
        post_path_target = urlparse(df2_target_url).path
        post_dir_target = os.path.dirname(post_path_target)
        post_base_target = os.path.basename(post_path_target)
        post_base_file_target = os.path.splitext(post_base_target)[0]
        url_list.append(post_base_file_target)
    logging.info('%s %s' % ('INFO List of existing post files', url_list))

    for a, b in df1_input.itertuples(index=False):
        df1_input_id = a
        df1_input_url = b
        df1_input_url_path = urllib.parse.urlparse(df1_input_url).path
        check_id = df2_target.loc[df2_target['ID'] == df1_input_id]
        if check_id.empty:
            logging.info('%s %s %s' % ('INFO Post with ID', df1_input_id, 'doesnot exist'))
        else:
            logging.info('%s %s %s' % ('INFO Post with ID', df1_input_id, 'exists. Checking guid...'))
            df2_target_url_index = df2_target.loc[df2_target['ID'] == df1_input_id, 'guid']
            df2_target_url = df2_target_url_index.to_string(index=False)
            df2_target_url_path =  urllib.parse.urlparse(df2_target_url).path
            if df1_input_url == df2_target_url:
                logging.info('%s %s' % ('INFO guid is matching, hence deleting post', df1_input_id))
                try:
                    df1_input_id = str(df1_input_id)
                    command_delete = 'wp --allow-root post delete '+df1_input_id+' --force'
                    process_delete = subprocess.check_output(command_delete,shell=True)
                    logging.info('%s %s' % ('INFO Successfully deleted post', df1_input_id))
                except subprocess.CalledProcessError as e:
                    logging.error('%s %s %s' % ('ERROR', 'Post delete failed', str(e)))
            elif df1_input_url_path == df2_target_url_path:
                logging.info('%s %s' % ('INFO guid/url path is matching, hence deleting post', df1_input_id))
                try:
                    df1_input_id = str(df1_input_id)
                    command_delete = 'wp --allow-root post delete '+df1_input_id+' --force'
                    process_delete = subprocess.check_output(command_delete,shell=True)
                    logging.info('%s %s' % ('INFO Successfully deleted post', df1_input_id))
                except subprocess.CalledProcessError as e:
                    logging.error('%s %s %s' % ('ERROR', 'Post delete failed', str(e)))
            else:
                logging.info('%s' % ('WARN guid is not matching'))

def main():
    logging.info('%s' % ('INFO Starting cleanup..'))
    appz_env = os.environ.get('APPZ_ENV')
    if appz_env is None:
        logging.error('%s' % ('ERROR APPZ_ENV is none hence could not identify the environment to be cleaned up'))
        sys.exit()
    else:
        logging.info('%s %s' % ('INFO APPZ_ENV is set to', appz_env))

        input_file = '/wp-contents/WebsiteCleanup/CleanupList_'+appz_env+'.xlsx'
        check_file = os.path.isfile(input_file)
        if check_file is False:
            logging.error('%s' % ('ERROR Input file doesnot exist'))
            sys.exit()
        else:
            logging.info('%s' % ('INFO Found input file'))
            cleanup_posts(input_file)
            logging.info('%s' % ('INFO Cleanup completed'))
            try:
                time_now  = datetime.datetime.now().strftime('%d_%m_%Y_%H_%M_%S')
                zip_file_name = basename(input_file)
                zip_final = zip_file_name.replace("xlsx", "zip")
                zip_dir_path = '/appz/backup/archives'
                isExist = os.path.exists(zip_dir_path)
                if not isExist:
                    os.makedirs(zip_dir_path)
                    logging.info('%s' % ('INFO Created the subfolder to store file purge inputs'))
                else:
                    logging.info('%s' % ('INFO Subfolder to store file purge inputs already exist'))
                zf = zipfile.ZipFile('/appz/backup/archives/'+time_now+'_'+zip_final+'', mode='w')
                zf.write(input_file, basename(input_file))
                zf.close()
                logging.info('%s' % ('INFO Successfully archived the input file'))
            except Exception as e:
                logging.error('%s %s' % ('ERROR Input file archiving failed', str(e)))

if __name__ == '__main__':
    main()

