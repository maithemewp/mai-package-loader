<?php
/**
 * Serves one timing per request from a long-running PHP process, so opcache
 * and the realpath cache stay warm between requests the way PHP-FPM keeps
 * them on a real site.
 *
 *   php -d opcache.enable_cli=1 -S 127.0.0.1:8431 -t <core> tests/perf-router.php
 */

if ( '/perf' !== parse_url( $_SERVER['REQUEST_URI'], PHP_URL_PATH ) ) {
	return false;
}

require $_SERVER['DOCUMENT_ROOT'] . '/wp-load.php';

$start = hrtime( true );
Mai\Demo\Info::VERSION;
printf( '%.3f', ( hrtime( true ) - $start ) / 1e6 );
exit;
