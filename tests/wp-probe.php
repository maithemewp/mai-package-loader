<?php
/**
 * Boots a throwaway WordPress and reports one thing about the shared library.
 *
 *   WP=<core dir> php wp-probe.php <check>
 *
 * PROBE_REQUEST, as JSON, becomes $_REQUEST before WordPress loads, to stand
 * in for the plugins screen activating a plugin.
 */

$_REQUEST = json_decode( (string) getenv( 'PROBE_REQUEST' ), true ) ?: [];

require getenv( 'WP' ) . '/wp-load.php';

$check = $argv[1];

switch ( $check ) {
	case 'early':
		// Recorded by the first plugin to load, while plugins were loading.
		echo $GLOBALS['mai_demo_early'] ?? 'unset';
		break;

	case 'early-deep':
		echo $GLOBALS['mai_demo_early_deep'] ?? 'unset';
		break;

	case 'dropin':
		echo $GLOBALS['mai_demo_dropin'] ?? 'unset';
		break;

	case 'mu-early':
		echo $GLOBALS['mai_demo_mu_early'] ?? 'unset';
		break;

	case 'copies':
		Mai\Demo\Info::VERSION;
		echo count( Mai_Package_Loader::discovered()['maithemewp/mai-demo'] ?? [] );
		break;

	case 'info':
		echo Mai\Demo\Info::VERSION;
		break;

	case 'deep':
		echo Mai\Demo\Sub\Deep::VERSION;
		break;

	case 'activate-later':
		// Activated after discovery has run: Info is already loaded and stays,
		// Deep is not and comes from the newly activated plugin's copy.
		require_once ABSPATH . 'wp-admin/includes/plugin.php';
		$early  = Mai\Demo\Info::VERSION;
		$result = activate_plugin( 'qqq-later/qqq-later.php' );
		echo is_wp_error( $result ) ? $result->get_error_message() : $early . ' ' . Mai\Demo\Sub\Deep::VERSION;
		break;

	case 'perf':
		$start = hrtime( true );
		$v     = Mai\Demo\Info::VERSION;
		printf( '%s %.3f', $v, ( hrtime( true ) - $start ) / 1e6 );
		break;

	default:
		echo 'unknown check';
}
