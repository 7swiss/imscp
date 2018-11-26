<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 * Copyright (C) 2010-2018 by Laurent Declercq <l.declercq@nuxwin.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace iMSCP\Exception\Writer;

use iMSCP\Application;
use iMSCP\Exception\Event;
use iMSCP\Functions\Mail as MailFunct;
use iMSCP\Utility\OpcodeCache;

/**
 * Class Mail
 *
 * @package iMSCP\Exception\Writer
 */
class Mail implements WriterInterface
{
    /**
     * @inheritdoc
     */
    public function __invoke(Event $event): void
    {
        $data = $this->prepareMailData($event->getException());

        if (empty($data)) {
            return;
        }

        $footprintsCacheFile = CACHE_PATH . '/mail_body_footprints.php';
        $footprints = [];
        $now = time();

        // Load footprints cache file
        if (is_readable($footprintsCacheFile)) {
            $footprints = include($footprintsCacheFile);

            if (!is_array($footprints)) {
                $footprints = [];
            }
        }

        # Remove expired entries from the cache
        foreach ($footprints as $footprint => $expireTime) {
            if ($expireTime <= $now) {
                unset($footprints[$footprint]);
            }
        }

        // Do not send mail for identical exception in next 24 hours
        if (array_key_exists($data['footprint'], $footprints)) {
            return;
        }

        MailFunct::sendMail($data);

        // Update footprints cache file
        $footprints[$data['footprint']] = strtotime('+24 hours');
        $fileContent = "<?php\n";
        $fileContent .= "// File automatically generated by i-MSCP. Do not edit it manually.\n";
        $fileContent .= "return " . var_export($footprints, true) . ";\n";
        @file_put_contents($footprintsCacheFile, $fileContent, LOCK_EX);
        OpcodeCache::clearAllActive($footprintsCacheFile); // Be sure to load newest version on next call
    }

    /**
     * Prepare mail
     *
     * @param \Throwable $exception An exception object
     * @return array Array containing mail data
     */
    protected function prepareMailData(\Throwable $exception): array
    {
        $data = [];

        try {
            $config = Application::getInstance()->getConfig();

            if (!isset($config['DEFAULT_ADMIN_ADDRESS'])) {
                return $data;
            }

            $message = preg_replace('/([\t\n]+|<br>)/', ' ', $exception->getMessage());

            $contextInfo = '';
            foreach (['HTTP_USER_AGENT', 'REQUEST_URI', 'HTTP_REFERER', 'REMOTE_ADDR', 'X-FORWARDED-FOR', 'SERVER_ADDR'] as $key) {
                if (isset($_SERVER[$key]) && $_SERVER[$key] !== '') {
                    $contextInfo .= ucwords(strtolower(str_replace('_', ' ', $key))) . ": {$_SERVER["$key"]}\n";
                }
            }

            return [
                'mail_id'      => 'exception-notification',
                'footprint'    => sha1($message),
                'username'     => 'administrator',
                'email'        => $config['DEFAULT_ADMIN_ADDRESS'],
                'subject'      => 'i-MSCP - An exception has been thrown',
                'message'      => <<<EOF
Dear {NAME},

An exception has been thrown in file {FILE} at line {LINE}:

==========================================================================
{EXCEPTION}
==========================================================================

Stack trace:
____________

{STRACK_TRACE}

Contextual information:
_______________________

{CONTEXT_INFO}

Note: You will not receive further emails for this exception in the next 24 hours.

Please do not reply to this email.

___________________________
i-MSCP Mailer
EOF
                ,
                'placeholders' => [
                    '{FILE}'         => $exception->getFile(),
                    '{LINE}'         => $exception->getLine(),
                    '{EXCEPTION}'    => $message,
                    '{STRACK_TRACE}' => $exception->getTraceAsString(),
                    '{CONTEXT_INFO}' => $contextInfo
                ]
            ];


        } catch (\Throwable $e) {
            return $data;
        }
    }
}
