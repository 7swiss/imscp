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

/***********************************************************************************************************************
 * Main
 */

require_once 'imscp-lib.php';

check_login('user');
Registry::get('iMSCP_Application')->getEventsManager()->dispatch(iMSCP_Events::onClientScriptStart);
customerHasFeature('domain_aliases') && isset($_GET['id']) or showBadRequestErrorPage();

$stmt = exec_query('DELETE FROM domain_aliasses WHERE alias_id = ? AND domain_id = ? AND alias_status = ?', [
    intval($_GET['id']), get_user_domain_id($_SESSION['user_id']), 'ordered'
]);

if ($stmt->rowCount()) {
    set_page_message(tr('Order successfully canceled.'), 'success');
    redirectTo('domains_manage.php');
}

showBadRequestErrorPage();
