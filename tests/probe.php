<?php
/**
 * Loads plugins' autoloaders in the order given, runs one check, prints JSON.
 *
 *   php probe.php <check> <plugin-dir>...
 *
 * Every warning and notice is turned into a failure, because a loader that
 * works but fills a site's log is not working.
 */

set_error_handler( static function ( int $no, string $message, string $file, int $line ): bool {
	fwrite( STDERR, "PHP warning: $message in $file:$line\n" );
	exit( 1 );
} );

$check   = $argv[1];
$plugins = array_slice( $argv, 2 );

foreach ( $plugins as $plugin ) {
	require $plugin . '/vendor/autoload.php';
}

$out = match ( $check ) {
	'info'      => Mai\Demo\Info::VERSION,
	'deep'      => Mai\Demo\Sub\Deep::VERSION,
	'global'    => Mai_Demo_Global::VERSION,
	'loader'    => Mai_Package_Loader::VERSION,
	'exists'    => var_export( class_exists( 'Mai\Demo\Info' ), true ),
	'missing'   => var_export( class_exists( 'Mai\Demo\Nope' ), true ),
	'mail'      => var_export( class_exists( 'MailPoet\Thing' ) || class_exists( 'Mailchimp_Thing' ) || class_exists( 'MainWP\Thing' ), true ) . ' ' . var_export( null === Mai_Package_Loader::discovered(), true ),
	'info-twice' => Mai\Demo\Info::VERSION . ' ' . ( in_array( ( new ReflectionClass( 'Mai_Package_Loader' ) )->getStaticPropertyValue( 'autoloader' ), spl_autoload_functions(), true ) ? 'still registered' : 'takeover' ),
	'nope-then-info' => var_export( class_exists( 'Mai\Demo\Nope' ), true ) . ' ' . Mai\Demo\Info::VERSION,
	'info-deep' => Mai\Demo\Info::VERSION . ' ' . Mai\Demo\Sub\Deep::VERSION,
	'rejected'  => ( static function (): string { class_exists( 'Mai\Demo\Info' ); $reasons = array_values( Mai_Package_Loader::rejected() ); sort( $reasons ); return implode( '|', $reasons ); } )(),
	'non-mai'   => var_export( class_exists( 'Acme\Thing' ), true ) . ' ' . var_export( null === Mai_Package_Loader::discovered(), true ),
	'both'      => Mai\Demo\Info::VERSION . ' ' . Mai_Demo_Global::VERSION,
	default     => 'unknown check',
};

echo $out;
