<?php
/**
 * Mai Package Loader.
 *
 * Loads the newest copy of each shared mai library, whichever plugin loads
 * first. See docs/specs/2026-10-03-mai-package-loader.md for the why.
 *
 * Loaded by Composer through this package's "files" entry. Composer runs that
 * entry once per request however many plugins bundle this package, so the
 * first plugin's copy of this class serves the whole request. That is why the
 * public API only ever grows: an old copy may be the one in charge.
 *
 * PHP 8.1, the lowest floor of any plugin that bundles it.
 */

declare( strict_types=1 );

defined( 'ABSPATH' ) || 'cli' === PHP_SAPI || exit;

if ( ! class_exists( 'Mai_Package_Loader', false ) ) {
	final class Mai_Package_Loader {
		/** This copy's version. Informational: the first copy loaded serves. */
		public const VERSION = '0.1.0';

		/** The file a shared library ships to declare itself. */
		public const DECLARATION = 'mai-package.php';

		/**
		 * Every class a shared library may own starts with this, so anything
		 * else is turned away before any work is done.
		 */
		private const PREFIX = 'Mai';

		/** Only libraries published under this vendor are looked for. */
		private const VENDOR = 'maithemewp';

		/** This package's own Composer name. */
		private const NAME = 'maithemewp/mai-package-loader';

		/**
		 * Library name to its copies, newest first. Null until the first
		 * request for a class starting with "Mai".
		 *
		 * @var array<string, array<int, array{name: string, version: string, dir: string, namespace: ?string, path: string, classes: array<string, string>}>>|null
		 */
		private static ?array $libraries = null;

		private static bool $booted = false;

		/**
		 * Puts the loader first in line, so it answers before an old library
		 * bootstrap that appended its own autoloader.
		 */
		public static function boot(): void {
			if ( self::$booted ) {
				return;
			}

			self::$booted = true;

			spl_autoload_register( [ self::class, 'load' ], true, true );

			// A plugin activated this request loads its files after discovery
			// may already have run. Its copies are added then, which helps
			// every class not loaded yet. One already loaded cannot be swapped.
			if ( function_exists( 'add_action' ) ) {
				add_action( 'activate_plugin', [ self::class, 'activating' ], 0 );

				// Must-use plugins are not in any list, and a drop-in may ask
				// before WordPress can read its lists at all. Looking again
				// after each loading stage helps every class not loaded yet.
				add_action( 'muplugins_loaded', [ self::class, 'refresh' ], PHP_INT_MIN );
				add_action( 'plugins_loaded', [ self::class, 'refresh' ], PHP_INT_MIN );
			}
		}

		/**
		 * Looks again for copies loaded since discovery ran. Does nothing if
		 * discovery has not run, since it will see them when it does.
		 */
		public static function refresh(): void {
			if ( null !== self::$libraries ) {
				self::$libraries = self::merge( self::$libraries, self::scan( self::roots() ) );
			}
		}

		public static function load( string $class ): void {
			if ( ! str_starts_with( $class, self::PREFIX ) ) {
				return;
			}

			self::$libraries ??= self::merge( [], self::scan( self::roots() ) );

			foreach ( self::$libraries as $copies ) {
				foreach ( $copies as $copy ) {
					$file = self::fileFor( $copy, $class );

					// Not this library's class. Every copy of a library owns
					// the same names, so there is no point asking the rest.
					if ( null === $file ) {
						break;
					}

					// Newest first. A copy whose file has gone, say from a
					// plugin deleted mid-request, falls back to the next.
					if ( is_readable( $file ) ) {
						require $file;

						return;
					}
				}
			}
		}

		/**
		 * What was found, for diagnostics. Null until discovery has run.
		 *
		 * @return array<string, array<int, array<string, mixed>>>|null
		 */
		public static function discovered(): ?array {
			return self::$libraries;
		}

		/**
		 * Adds the copies of a plugin being activated this request.
		 *
		 * @param mixed $plugin Plugin basename, from `activate_plugin`.
		 */
		public static function activating( $plugin = '' ): void {
			if ( null === self::$libraries || ! is_string( $plugin ) || ! defined( 'WP_PLUGIN_DIR' ) ) {
				return;
			}

			$vendor = self::pluginVendor( WP_PLUGIN_DIR, $plugin );

			if ( null !== $vendor ) {
				self::$libraries = self::merge( self::$libraries, self::scan( [ $vendor ] ) );
			}
		}

		/**
		 * The vendor folders to look in.
		 *
		 * Composer's registered loaders come first: they cover everything
		 * already loaded, must-use plugins included. WordPress's lists of
		 * active plugins and the active theme are what let a library be used
		 * before most plugins have loaded.
		 *
		 * @return array<int, string>
		 */
		private static function roots(): array {
			$roots  = [];
			$loader = 'Composer\Autoload\ClassLoader';

			if ( class_exists( $loader, false ) && method_exists( $loader, 'getRegisteredLoaders' ) ) {
				foreach ( array_keys( $loader::getRegisteredLoaders() ) as $vendor ) {
					$roots[] = (string) $vendor;
				}
			}

			if ( self::optionsReady() ) {
				foreach ( self::activePlugins() as $plugin ) {
					$vendor = self::pluginVendor( WP_PLUGIN_DIR, $plugin );

					if ( null !== $vendor ) {
						$roots[] = $vendor;
					}
				}

				foreach ( self::themeDirs() as $theme ) {
					$roots[] = $theme . '/vendor';
				}
			}

			// Composer's list and the plugin list name the same folders, so
			// one entry per path. Resolving every path to catch symlinks cost
			// more than everything else here put together; a symlinked folder
			// read twice is harmless, because merge() counts each copy once
			// by its real folder.
			$unique = [];

			foreach ( $roots as $root ) {
				$unique[ rtrim( $root, '/' ) ] = true;
			}

			return array_keys( $unique );
		}

		/**
		 * Whether WordPress can answer `get_option()` safely yet.
		 *
		 * Not in a drop-in such as object-cache.php, which runs before the
		 * object cache exists. There, Composer's list is all there is.
		 */
		private static function optionsReady(): bool {
			return function_exists( 'get_option' )
				&& defined( 'WP_PLUGIN_DIR' )
				&& isset( $GLOBALS['wpdb'], $GLOBALS['wp_object_cache'] );
		}

		/**
		 * Active plugins, network-active ones too, and any being activated by
		 * this request through the plugins screen.
		 *
		 * @return array<int, string> Plugin basenames.
		 */
		private static function activePlugins(): array {
			$plugins = array_values( array_filter( (array) get_option( 'active_plugins', [] ), 'is_string' ) );

			if ( function_exists( 'is_multisite' ) && is_multisite() && function_exists( 'get_site_option' ) ) {
				$plugins = array_merge( $plugins, array_keys( (array) get_site_option( 'active_sitewide_plugins', [] ) ) );
			}

			return array_merge( $plugins, self::activatingFromRequest() );
		}

		/**
		 * Plugins the plugins screen is activating in this request.
		 *
		 * The nonce is not checked: this only decides which folders are
		 * looked in, and the request fails later if the nonce is wrong. Seen
		 * this early, the activating plugin's copy can win from the start.
		 *
		 * @return array<int, string>
		 */
		private static function activatingFromRequest(): array {
			// phpcs:disable WordPress.Security.NonceVerification
			$action = isset( $_REQUEST['action'] ) && is_string( $_REQUEST['action'] ) ? $_REQUEST['action'] : '';

			if ( 'activate' === $action && isset( $_REQUEST['plugin'] ) && is_string( $_REQUEST['plugin'] ) ) {
				return [ $_REQUEST['plugin'] ];
			}

			if ( 'activate-selected' === $action && isset( $_REQUEST['checked'] ) && is_array( $_REQUEST['checked'] ) ) {
				return array_values( array_filter( $_REQUEST['checked'], 'is_string' ) );
			}
			// phpcs:enable

			return [];
		}

		/**
		 * The active theme and its parent.
		 *
		 * @return array<int, string>
		 */
		private static function themeDirs(): array {
			$dirs = [];

			foreach ( [ 'stylesheet', 'template' ] as $option ) {
				$slug = get_option( $option );

				if ( ! is_string( $slug ) || '' === $slug || str_contains( $slug, '..' ) ) {
					continue;
				}

				// WordPress's own answer. With one themes folder, the usual
				// case, it reads no options; reading stylesheet_root directly
				// cost a database query per page, since it rarely exists.
				$root = function_exists( 'get_theme_root' ) ? get_theme_root( $slug ) : WP_CONTENT_DIR . '/themes';

				$dirs[] = rtrim( $root, '/' ) . '/' . $slug;
			}

			return $dirs;
		}

		/** A plugin's vendor folder, or null for a single-file plugin. */
		private static function pluginVendor( string $pluginsDir, string $plugin ): ?string {
			$folder = dirname( $plugin );

			if ( '.' === $folder || '' === $folder || str_contains( $plugin, '..' ) ) {
				return null;
			}

			return rtrim( $pluginsDir, '/' ) . '/' . $folder . '/vendor';
		}

		/**
		 * Reads every declaration under each vendor folder.
		 *
		 * @param array<int, string> $vendors
		 * @return array<int, array<string, mixed>>
		 */
		private static function scan( array $vendors ): array {
			$copies = [];

			foreach ( $vendors as $vendor ) {
				foreach ( self::declarations( $vendor ) as $file ) {
					$copy = self::read( $file );

					if ( null !== $copy ) {
						$copies[] = $copy;
					}
				}
			}

			return $copies;
		}

		/**
		 * The declaration files in one vendor folder.
		 *
		 * Read from Composer's own record of what it installed and where.
		 * With opcache that record costs next to nothing to include, where
		 * listing folders costs a directory read per plugin on every page.
		 * It also finds a package Composer installed somewhere custom.
		 *
		 * @return array<int, string>
		 */
		private static function declarations( string $vendor ): array {
			$record = $vendor . '/composer/installed.php';

			// Composer 1 wrote no such record. Listing the folder still works.
			if ( ! is_file( $record ) ) {
				return glob( $vendor . '/' . self::VENDOR . '/*/' . self::DECLARATION ) ?: [];
			}

			try {
				$installed = ( static fn( string $path ): mixed => include $path )( $record );
			} catch ( Throwable ) {
				return [];
			}

			$files = [];

			foreach ( is_array( $installed['versions'] ?? null ) ? $installed['versions'] : [] as $name => $package ) {
				// This package never declares itself, and every library brings it.
				if ( ! is_string( $name ) || ! str_starts_with( $name, self::VENDOR . '/' ) || self::NAME === $name || ! is_string( $package['install_path'] ?? null ) ) {
					continue;
				}

				$file = $package['install_path'] . '/' . self::DECLARATION;

				if ( is_file( $file ) ) {
					$files[] = $file;
				}
			}

			return $files;
		}

		/**
		 * Adds copies to what is known, keeping each library newest first.
		 *
		 * @param array<string, array<int, array<string, mixed>>> $known
		 * @param array<int, array<string, mixed>>                $copies
		 * @return array<string, array<int, array<string, mixed>>>
		 */
		private static function merge( array $known, array $copies ): array {
			foreach ( $copies as $copy ) {
				// The same folder found twice, through two lists, is one copy.
				foreach ( $known[ $copy['name'] ] ?? [] as $existing ) {
					if ( $existing['dir'] === $copy['dir'] ) {
						continue 2;
					}
				}

				$known[ $copy['name'] ][] = $copy;
			}

			foreach ( $known as $name => $list ) {
				// Stable since PHP 8.0, so the same version found twice keeps
				// the one found first.
				usort( $list, static fn( array $a, array $b ): int => version_compare( $b['version'], $a['version'] ) );

				$known[ $name ] = $list;
			}

			return $known;
		}

		/**
		 * One declaration, or null if it cannot be trusted.
		 *
		 * Anything unexpected skips the copy rather than guessing. A newer
		 * declaration may carry keys this copy does not know, and those are
		 * ignored.
		 *
		 * @return array<string, mixed>|null
		 */
		private static function read( string $file ): ?array {
			try {
				$data = ( static fn( string $path ): mixed => include $path )( $file );
			} catch ( Throwable ) {
				return null;
			}

			if ( ! is_array( $data ) ) {
				return null;
			}

			$name    = $data['name'] ?? null;
			$version = $data['version'] ?? null;

			if ( ! is_string( $name ) || '' === $name || ! is_string( $version ) || ! preg_match( '/^\d+(\.\d+){0,3}(-[0-9A-Za-z.]+)?$/', $version ) ) {
				return null;
			}

			$namespace = $data['namespace'] ?? null;
			$namespace = is_string( $namespace ) && str_starts_with( $namespace, self::PREFIX ) ? rtrim( $namespace, '\\' ) . '\\' : null;

			$classes = [];

			foreach ( is_array( $data['classes'] ?? null ) ? $data['classes'] : [] as $class => $relative ) {
				if ( is_string( $class ) && str_starts_with( $class, self::PREFIX ) && is_string( $relative ) && ! str_contains( $relative, '..' ) ) {
					$classes[ $class ] = $relative;
				}
			}

			if ( null === $namespace && [] === $classes ) {
				return null;
			}

			$path = $data['path'] ?? '';
			$dir  = realpath( dirname( $file ) );

			if ( false === $dir || ! is_string( $path ) || str_contains( $path, '..' ) ) {
				return null;
			}

			return [
				'name'      => $name,
				'version'   => $version,
				'dir'       => $dir,
				'namespace' => $namespace,
				'path'      => trim( $path, '/' ),
				'classes'   => $classes,
			];
		}

		/**
		 * Where a copy keeps a class, or null if the class is not its.
		 *
		 * @param array<string, mixed> $copy
		 */
		private static function fileFor( array $copy, string $class ): ?string {
			if ( isset( $copy['classes'][ $class ] ) ) {
				return $copy['dir'] . '/' . ltrim( $copy['classes'][ $class ], '/' );
			}

			if ( null !== $copy['namespace'] && str_starts_with( $class, $copy['namespace'] ) ) {
				$relative = str_replace( '\\', '/', substr( $class, strlen( $copy['namespace'] ) ) );
				$base     = '' === $copy['path'] ? $copy['dir'] : $copy['dir'] . '/' . $copy['path'];

				return $base . '/' . $relative . '.php';
			}

			return null;
		}
	}
}

Mai_Package_Loader::boot();
