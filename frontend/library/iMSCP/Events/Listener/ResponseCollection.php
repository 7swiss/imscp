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

/**
 * Class iMSCP_Events_Listener_ResponseCollection
 */
class iMSCP_Events_Listener_ResponseCollection extends SplStack
{
    /**
     * @var bool
     */
    protected $isStopped = false;

    /**
     * Did the last response provided trigger a short circuit of the stack?
     *
     * @return bool
     */
    public function isStopped()
    {
        return $this->isStopped;
    }

    /**
     * Mark the collection as stopped (or its opposite)
     *
     * @param  bool $flag
     * @return iMSCP_Events_Listener_ResponseCollection
     */
    public function setStopped($flag)
    {
        $this->isStopped = (bool)$flag;
        return $this;
    }

    /**
     * Convenient access to the first listener method return value.
     *
     * @return mixed The first handler return value
     */
    public function first()
    {
        return parent::bottom();
    }

    /**
     * Convenient access to the last listener method return value.
     *
     * If the collection is empty, returns null. Otherwise, returns value
     * returned by last handler.
     *
     * @return mixed The last handler return value
     */
    public function last()
    {
        if (count($this) === 0) {
            return NULL;
        }

        return parent::top();
    }

    /**
     * Check if any of the responses match the given value.
     *
     * @param  mixed $value The value to look for among responses
     * @return bool
     */
    public function contains($value)
    {
        foreach ($this as $response) {
            if ($response === $value) {
                return true;
            }
        }

        return false;
    }
}
