<?php
/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the
 * installation. You don't have to use the web site, you can
 * copy this file to "wp-config.php" and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * MySQL settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * @link https://codex.wordpress.org/Editing_wp-config.php
 *
 * @package WordPress
 */

// ** MySQL settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define('DB_NAME', getenv('MYSQL_DATABASE'));

/** MySQL database username */
define('DB_USER',getenv('MYSQL_USER'));

/** MySQL database password */
define('DB_PASSWORD',getenv('MYSQL_PASSWORD'));

/** MySQL hostname */
define('DB_HOST',getenv('MYSQL_HOST'));

/** Database Charset to use in creating database tables. */
define('DB_CHARSET', 'utf8mb4');

/** The Database Collate type. Don't change this if in doubt. */
define('DB_COLLATE', '');

/**#@+
 * Authentication Unique Keys and Salts.
 *
 * Change these to different unique phrases!
 * You can generate these using the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}
 * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define('AUTH_KEY',         'uN$qdc<+r5>%qh[WBn~VhI6V^Mg9V8DnyX9GpQ3xMtY tri=tn>17c4n7v-|jiL(');
define('SECURE_AUTH_KEY',  'S)<P(AhwWG6#^UZ $kXgScx=EH1]rb:OiyHCH.FP$JWI)o]p6,<{}Eemk?wb6S:,');
define('LOGGED_IN_KEY',    'Ev%c 4gWTuQE5R~i%K0Q}cq!ro1;SRxVG8Fzt24*Cv`$T%oLu0l^O*H_=!cXC4O]');
define('NONCE_KEY',        '7?P1*S/Upwv nBKro6gAcXiyG&SZ4#HlbH`<h<(b^Ia%r)>`q5OB(t^P$pB:PgI0');
define('AUTH_SALT',        'iE(fqM|Mq#huGJ{zo][N[&=22!v|0M[W@8[FH-&:A<dUA[., o(iSlK}b:cXpVpg');
define('SECURE_AUTH_SALT', '#>S|MuRP!/WFt~:<xTN^j`5.jl#_Qs22|%,=;qZ_pUb%_%y#*COev`nCxG~cqVak');
define('LOGGED_IN_SALT',   'g+K((Kr/f+!B5%0]FTDDK9XlSnSbOrzyQ&yZKu`FTa@_C5MmlgpxtKU>4a2aSuaS');
define('NONCE_SALT',       '&[]9cj1#S2hoYY/r$oHkTizv.Lag;P5$7/?c%md(U=s@bGQ&Cc `C,%Cn!p%GavJ');

/**#@-*/

/**
 * WordPress Database Table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix  = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the Codex.
 *
 * @link https://codex.wordpress.org/Debugging_in_WordPress
 */
define( 'WP_AUTO_UPDATE_CORE', false ); 
if (getenv('WP_DEBUG') == 'true') {
	define( 'WP_DEBUG', true );
	define( 'WP_DEBUG_DISPLAY', false );
	define( 'WP_DEBUG_LOG', '/appz/log/wp_debug.log' );
}
else
	define( 'WP_DEBUG', false );
	
define('DISABLE_WP_CRON', true);
/* That's all, stop editing! Happy blogging. */

/** Absolute path to the WordPress directory. */
if ( !defined('ABSPATH') )
        define('ABSPATH', dirname(__FILE__) . '/');
        
/** SSL */  
define('FORCE_SSL_ADMIN', getenv("X_APPZ_ENV") !== false);
// in some setups HTTP_X_FORWARDED_PROTO might contain
// a comma-separated list e.g. http,https
// so check for https existence
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https'){
 $_SERVER['HTTPS']='on';
}
define( 'SMTP_USER',   getenv('SMTP_USER') );    	// Username to use for SMTP authentication
define( 'SMTP_PASS',   getenv('SMTP_PASS') );       // Password to use for SMTP authentication
define( 'SMTP_HOST',   getenv('SMTP_HOST') );    	// The hostname of the mail server
define( 'SMTP_FROM',   getenv('SMTP_FROM') ); 		// SMTP From email address
define( 'SMTP_NAME',   getenv('SMTP_NAME') );   	// SMTP From name
define( 'SMTP_PORT',   getenv('SMTP_PORT') );       // SMTP port number - likely to be 25, 465 or 587
define( 'SMTP_SECURE', getenv('SMTP_SECURE') );     // Encryption system to use - ssl or tls
define( 'SMTP_AUTH',   getenv('SMTP_AUTH') == 'true' );    // Use SMTP authentication (true|false)
define( 'SMTP_DEBUG',  intval(getenv('SMTP_DEBUG')) );     // for debugging purposes only set to 1 or 2       

/** Sets up WordPress vars and included files. */
require_once(ABSPATH . 'wp-settings.php');

