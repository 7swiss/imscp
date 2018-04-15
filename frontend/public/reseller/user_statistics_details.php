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

use iMSCP\TemplateEngine;
use iMSCP_Events as Events;
use iMSCP_Registry as Registry;

/**
 * Get traffic data for the given user and period
 *
 * @param int $domainId User main domain unique identifier
 * @param int $startDate An UNIX timestamp representing a start date
 * @param int $endDate An UNIX timestamp representing an end date
 * @return array
 */
function getUserTraffic($domainId, $startDate, $endDate)
{
    static $stmt;

    if (NULL === $stmt) {
        /** @var iMSCP_Database $db */
        $db = Registry::get('iMSCP_Application')->getDatabase();
        $stmt = $db->prepare(
            '
               SELECT IFNULL(SUM(dtraff_web), 0) AS web_traffic,
                    IFNULL(SUM(dtraff_ftp), 0) AS ftp_traffic,
                    IFNULL(SUM(dtraff_mail), 0) AS smtp_traffic,
                    IFNULL(SUM(dtraff_pop),0) AS pop_traffic
                FROM domain_traffic
                WHERE domain_id = ?
                AND dtraff_time BETWEEN ? AND ?
            '
        );
    }

    $stmt->execute([$domainId, $startDate, $endDate]);

    if (!$stmt->rowCount()) {
        return [0, 0, 0, 0];
    }

    $row = $stmt->fetch();

    return [$row['web_traffic'], $row['ftp_traffic'], $row['smtp_traffic'], $row['pop_traffic']];
}

/**
 * Generate domain statistics for the given period
 *
 * @param TemplateEngine $tpl Template engine instance
 * @return void
 */
function generatePage(TemplateEngine $tpl)
{
    $userId = intval($_GET['user_id']);
    $stmt = execQuery('SELECT admin_name, domain_id FROM admin JOIN domain ON(domain_admin_id = admin_id) WHERE admin_id = ? AND created_by = ?', [
        $userId, $_SESSION['user_id']
    ]);
    $stmt->rowCount() or showBadRequestErrorPage();
    $row = $stmt->fetch();
    $domainId = $row['domain_id'];
    $adminName = decodeIdna($row['admin_name']);
    $month = isset($_GET['month']) ? filterDigits($_GET['month']) : date('n');
    $year = isset($_GET['year']) ? filterDigits($_GET['year']) : date('Y');
    $stmt = execQuery('SELECT dtraff_time FROM domain_traffic WHERE domain_id = ? ORDER BY dtraff_time ASC LIMIT 1', [$domainId]);
    $nPastYears = $stmt->rowCount() ? date('Y') - date('Y', $stmt->fetchColumn()) : 0;

    generateDMYlists($tpl, 0, $month, $year, $nPastYears);

    $stmt = execQuery('SELECT domain_id FROM domain_traffic WHERE domain_id = ? AND dtraff_time BETWEEN ? AND ? LIMIT 1', [
        $domainId, getFirstDayOfMonth($month, $year), getLastDayOfMonth($month, $year)
    ]);

    if (!$stmt->rowCount()) {
        setPageMessage(tr('No statistics found for the given period. Try another period.'), 'static_info');
        $tpl->assign([
            'USERNAME'                      => toHtml($adminName),
            'USER_ID'                       => toHtml($userId),
            'USER_STATISTICS_DETAILS_BLOCK' => ''
        ]);
        return;
    }

    $requestedPeriod = getLastDayOfMonth($month, $year);
    $toDay = ($requestedPeriod < time()) ? date('j', $requestedPeriod) : date('j');
    $dateFormat = Registry::get('config')['DATE_FORMAT'];
    $all = array_fill(0, 8, 0);

    for ($fromDay = 1; $fromDay <= $toDay; $fromDay++) {
        $beginTime = mktime(0, 0, 0, $month, $fromDay, $year);
        $endTime = mktime(23, 59, 59, $month, $fromDay, $year);
        list($webTraffic, $ftpTraffic, $smtpTraffic, $popTraffic) = getUserTraffic($domainId, $beginTime, $endTime);
        $tpl->assign([
            'DATE'         => date($dateFormat, strtotime($year . '-' . $month . '-' . $fromDay)),
            'WEB_TRAFFIC'  => bytesHuman($webTraffic),
            'FTP_TRAFFIC'  => bytesHuman($ftpTraffic),
            'SMTP_TRAFFIC' => bytesHuman($smtpTraffic),
            'POP3_TRAFFIC' => bytesHuman($popTraffic),
            'ALL_TRAFFIC'  => bytesHuman($webTraffic + $ftpTraffic + $smtpTraffic + $popTraffic),
        ]);
        $all[0] += $webTraffic;
        $all[1] += $ftpTraffic;
        $all[2] += $smtpTraffic;
        $all[3] += $popTraffic;
        $tpl->parse('TRAFFIC_TABLE_ITEM', '.traffic_table_item');
    }

    $tpl->assign([
        'USER_ID'          => toHtml($userId),
        'USERNAME'         => toHtml($adminName),
        'ALL_WEB_TRAFFIC'  => toHtml(bytesHuman($all[0])),
        'ALL_FTP_TRAFFIC'  => toHtml(bytesHuman($all[1])),
        'ALL_SMTP_TRAFFIC' => toHtml(bytesHuman($all[2])),
        'ALL_POP3_TRAFFIC' => toHtml(bytesHuman($all[3])),
        'ALL_ALL_TRAFFIC'  => toHtml(bytesHuman(array_sum($all)))
    ]);
}

require 'imscp-lib.php';

checkLogin('reseller');
Registry::get('iMSCP_Application')->getEventsManager()->dispatch(Events::onResellerScriptStart);
resellerHasCustomers() && isset($_GET['user_id']) or showBadRequestErrorPage();

$tpl = new TemplateEngine();
$tpl->define([
    'layout'                        => 'shared/layouts/ui.tpl',
    'page'                          => 'reseller/user_statistics_details.tpl',
    'page_message'                  => 'layout',
    'month_list'                    => 'page',
    'year_list'                     => 'page',
    'user_statistics_details_block' => 'page',
    'traffic_table_item'            => 'user_statistics_details_block'
]);
$tpl->assign([
    'TR_PAGE_TITLE'   => toHtml(tr('Reseller / Statistics / Overview / {USERNAME} USER Statistics')),
    'TR_MONTH'        => toHtml(tr('Month')),
    'TR_YEAR'         => toHtml(tr('Year')),
    'TR_SHOW'         => toHtml(tr('Show')),
    'TR_WEB_TRAFFIC'  => toHtml(tr('Web traffic')),
    'TR_FTP_TRAFFIC'  => toHtml(tr('FTP traffic')),
    'TR_SMTP_TRAFFIC' => toHtml(tr('SMTP traffic')),
    'TR_POP3_TRAFFIC' => toHtml(tr('POP3/IMAP traffic')),
    'TR_ALL_TRAFFIC'  => toHtml(tr('All traffic')),
    'TR_ALL'          => toHtml(tr('All')),
    'TR_DAY'          => toHtml(tr('Day'))
]);

generateNavigation($tpl);
generatePage($tpl);
generatePageMessage($tpl);
$tpl->parse('LAYOUT_CONTENT', 'page');
Registry::get('iMSCP_Application')->getEventsManager()->dispatch(Events::onResellerScriptEnd, ['templateEngine' => $tpl]);
$tpl->prnt();
unsetMessages();
