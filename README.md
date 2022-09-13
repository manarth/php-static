# Statically-compiled PHP

This Docker definition compiles PHP and exports statically-linked executables
of PHP-CLI and PHP-FPM for use in containerisation.

## Usage

Run `docker build -t php-static`

## References

- [PHP source code](https://github.com/php/php-src)
- [PHP documentation](https://www.php.net/)

## Files available in the container

- `/usr/bin/php`
- `/usr/sbin/php-fpm`
- `/etc/php/php.ini`
- `/etc/php/php-fpm.conf`
- `/etc/php/php-fpm.d/www.conf.EXAMPLE`
- `/etc/ssl/certs`

## License

- The PHP License, version 3.01.
