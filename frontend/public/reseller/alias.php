<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 * Copyright (C) 2010-2018 by i-MSCP Team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

use iMSCP_Registry as Registry;
use iMSCP\TemplateEngine;

/***********************************************************************************************************************
 * Functions
 */

/**
 * Get table data
 *
 * @return array
 */
function reseller_getDatatable()
{
    $columns = ['alias_name', 'alias_mount', 'url_forward', 'admin_name'];
    $columnAliases = ['t1.alias_name', 't1.alias_mount', 't1.url_forward', 't3.admin_name'];
    $nbColumns = count($columns);

    /* Paging */
    $limit = '';

    if (isset($_GET['iDisplayStart'])
        && isset($_GET['iDisplayLength'])
        && $_GET['iDisplayLength'] != '-1'
    ) {
        $limit = 'LIMIT ' . intval($_GET['iDisplayStart']) . ', ' . intval($_GET['iDisplayLength']);
    }

    /* Ordering */
    $order = '';

    if (isset($_GET['iSortCol_0'])) {
        $order = 'ORDER BY ';

        if (isset($_GET['iSortingCols'])) {
            $iSortingCols = intval($_GET['iSortingCols']);

            for ($i = 0; $i < $iSortingCols; $i++) {
                if (isset($_GET['iSortCol_' . $i])
                    && isset($_GET['bSortable_' . intval($_GET['iSortCol_' . $i])])
                    && $_GET['bSortable_' . intval($_GET['iSortCol_' . $i])] == 'true'
                    && isset($_GET['sSortDir_' . $i])
                    && in_array($_GET['sSortDir_' . $i], ['asc', 'desc'], true)
                ) {
                    $order .= $columnAliases[intval($_GET['iSortCol_' . $i])] . ' ' . $_GET['sSortDir_' . $i] . ', ';
                }
            }
        }

        $order = substr_replace($order, '', -2);
        if ($order == 'ORDER BY') {
            $order = '';
        }
    }

    /* Filtering */
    $where = 'WHERE t3.created_by = ' . quoteValue($_SESSION['user_id'], PDO::PARAM_INT) . " AND t1.alias_status = 'ordered'";

    if (isset($_GET['sSearch'])
        && $_GET['sSearch'] != ''
    ) {
        $where .= ' AND (';
        for ($i = 0; $i < $nbColumns; $i++) {
            $where .= "{$columnAliases[$i]} LIKE " . quoteValue("%{$_GET['sSearch']}%") . ' OR ';
        }

        $where = substr_replace($where, '', -3);
        $where .= ')';
    }

    /* Individual column filtering */
    for ($i = 0; $i < $nbColumns; $i++) {
        if (isset($_GET["bSearchable_$i"]) && $_GET["bSearchable_$i"] == 'true' && isset($_GET["sSearch_$i"]) && $_GET["sSearch_$i"] != '') {
            $where .= "AND {$columnAliases[$i]} LIKE " . quoteValue("%{$_GET["sSearch_$i"]}%");
        }
    }

    /* Get data to display */
    $rResult = execute_query(
        "
            SELECT SQL_CALC_FOUND_ROWS t1.alias_id, " . implode(', ', $columnAliases) . "
            FROM domain_aliases AS t1
            JOIN domain AS t2 USING(domain_id)
            JOIN admin AS t3 ON(t3.admin_id = t2.domain_admin_id)
            $where $order $limit
        "
    );

    /* Total records after filtering (without limit) */
    $stmt = execute_query('SELECT FOUND_ROWS()');
    $iTotalDisplayRecords = $stmt->fetch(PDO::FETCH_NUM);
    $iTotalDisplayRecords = $iTotalDisplayRecords[0];

    /* Total record before any filtering */
    $stmt = exec_query(
        "
            SELECT COUNT(t1.alias_id)
            FROM domain_aliases AS t1
            JOIN domain AS t2 USING(domain_id)
            JOIN admin AS t3 ON(t3.admin_id = t2.domain_admin_id)
            WHERE t3.created_by = ?
            AND t1.alias_status = 'ordered'
        ",
        [$_SESSION['user_id']]
    );
    $iTotalRecords = $stmt->fetch(PDO::FETCH_NUM);
    $iTotalRecords = $iTotalRecords[0];

    /* Output */
    $output = [
        'sEcho'                => intval($_GET['sEcho']),
        'iTotalDisplayRecords' => $iTotalDisplayRecords,
        'iTotalRecords'        => $iTotalRecords,
        'aaData'               => []
    ];

    $trDelete = tr('Reject order');
    $trActivate = tr('Validate order');

    while ($data = $rResult->fetch()) {
        $row = [];
        $aliasName = decode_idna($data['alias_name']);

        for ($i = 0; $i < $nbColumns; $i++) {
            if ($columns[$i] == 'alias_name') {
                $row[$columns[$i]] = '<span class="icon i_disabled">' . decode_idna($data[$columns[$i]]) . '</span>';
            } elseif ($columns[$i] == 't3.admin_name') {
                $row[$columns[$i]] = tohtml(decode_idna($data[$columns[$i]]));
            } else {
                $row[$columns[$i]] = tohtml($data[$columns[$i]]);
            }
        }

        $actions = "<a href=\"alias_order.php?action=validate&id={$data['alias_id']}\" class=\"icon i_open\">$trActivate</a>";
        $actions .= "\n<a href=\"alias_order.php?action=reject&id={$data['alias_id']}\" "
            . "onclick=\"return delete_alias_order(this, '" . tojs($aliasName) . "')\" class=\"icon i_close\">$trDelete</a>";
        $row['actions'] = $actions;
        $output['aaData'][] = $row;
    }

    return $output;
}

/***********************************************************************************************************************
 * Main
 */

require 'imscp-lib.php';

check_login('reseller');
Registry::get('iMSCP_Application')->getEventsManager()->dispatch(iMSCP_Events::onResellerScriptStart);
resellerHasFeature('domain_aliases') && resellerHasCustomers() or showBadRequestErrorPage();

if (is_xhr()) {
    header('Cache-Control: no-cache, must-revalidate');
    header('Expires: Mon, 26 Jul 1997 05:00:00 GMT');
    header('Content-type: application/json');
    header('Status: 200 OK');
    echo json_encode(reseller_getDatatable());
    exit;
}

/** @var $tpl TemplateEngine */
$tpl = new TemplateEngine();
$tpl->define([
    'layout'         => 'shared/layouts/ui.tpl',
    'page'           => 'reseller/alias.tpl',
    'page_message'   => 'layout'
]);
$tpl->assign([
    'TR_PAGE_TITLE'                 => tr('Reseller / Customers / Ordered Domain Aliases'),
    'TR_ALIAS_NAME'                 => tr('Domain alias name'),
    'TR_MOUNT_POINT'                => tr('Mount point'),
    'TR_FORWARD_URL'                => tr('Forward URL'),
    'TR_STATUS'                     => tr('Status'),
    'TR_CUSTOMER'                   => tr('Customer'),
    'TR_ACTIONS'                    => tr('Actions'),
    'TR_MESSAGE_REJECT_ALIAS_ORDER' => tojs(tr('Are you sure you want to reject the order for the %s domain alias?', '%s')),
    'TR_PROCESSING_DATA'            => tr('Processing...')
]);

Registry::get('iMSCP_Application')->getEventsManager()->registerListener('onGetJsTranslations', function ($e) {
    /** @var $e \iMSCP_Events_Event */
    $e->getParam('translations')->core['dataTable'] = getDataTablesPluginTranslations(false);
});

generateNavigation($tpl);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
Registry::get('iMSCP_Application')->getEventsManager()->dispatch(iMSCP_Events::onResellerScriptEnd, ['templateEngine' => $tpl]);
$tpl->prnt();

unsetMessages();
