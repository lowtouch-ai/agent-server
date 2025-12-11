<?php 

// For using a mssql database conection is necessary the mssql drivers

// Here you put the database host
$serverName = "nhpri.database.windows.net"; //serverName\instanceName

// Database is the database name, UID is the user of the database, PWD is the password of the database.
$connectionInfo = array( "Database"=>"members", "UID"=>"gladworks", "PWD"=>"Explore545!");


$mydb = sqlsrv_connect( $serverName, $connectionInfo);


require_once('memberslookup.inc.php');

require_once('databaselookupfunc.inc.php');

