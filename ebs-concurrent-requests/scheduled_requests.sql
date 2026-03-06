WITH
  base AS (
      SELECT
          r.request_id                   AS requestId,
          p.user_concurrent_program_name AS programName,
          r.description,
          s.user_name                    AS requester,
          c.class_type                   AS classType,
          c.class_info                   AS classInfo, 
          NVL(r.actual_completion_date, r.last_update_date) AS lastRunDate,   
          r.requested_start_date                            AS nextRunDate,  
          flvStatus.meaning                                 AS lastRunStatus
      FROM
          apps.fnd_concurrent_requests r
          JOIN apps.fnd_conc_release_classes c
            ON c.application_id  = r.release_class_app_id
           AND c.release_class_id = r.release_class_id
          JOIN apps.fnd_concurrent_programs_tl p
            ON p.concurrent_program_id = r.concurrent_program_id
          JOIN apps.fnd_user s
            ON r.requested_by = s.user_id
          LEFT JOIN apps.fnd_lookup_values flvStatus
            ON flvStatus.lookup_type      = 'CP_STATUS_CODE'
           AND flvStatus.lookup_code      = r.status_code 
           AND NVL(flvStatus.enabled_flag,'Y') = 'Y' 
           AND flvStatus.start_date_active IS NOT NULL 
      WHERE
          r.phase_code    = 'P'
          AND NVL(c.date2, SYSDATE + 1) > SYSDATE
          AND c.class_type IS NOT NULL
          AND UPPER(NVL(r.description, p.user_concurrent_program_name)) LIKE 'NAME_PREFIX%'
  ),
  dates AS (
      SELECT
          b.requestId AS requestId,
          LISTAGG(TO_CHAR(lvl), ', ') WITHIN GROUP (ORDER BY lvl) AS dates
      FROM
          base b
          CROSS JOIN (SELECT LEVEL AS lvl FROM dual CONNECT BY LEVEL <= 31)
      WHERE
          b.classType            = 'S'
          AND SUBSTR(b.classInfo, lvl, 1) = '1'
      GROUP BY b.requestId
  )
SELECT
    b.requestId,
    NVL2(b.description,
        b.description || ' (' || b.programName || ')',
        b.programName
    )                                                          AS concProg,
    b.requester,
    lastRunDate,   
    nextRunDate,  
    lastRunStatus,
    DECODE(b.classType,
        'P', 'Periodic',
        'S', 'On Specific Days',
        'X', 'Advanced',
        b.classType
    )                                                          AS scheduleType,
    CASE
        WHEN b.classType = 'P' THEN
            'Repeat every '
            || SUBSTR(b.classInfo, 1, INSTR(b.classInfo, ':') - 1)
            || DECODE(SUBSTR(b.classInfo, INSTR(b.classInfo,':', 1, 1) + 1, 1),
                'N', ' minutes', 'H', ' hours', 'D', ' days', 'M', ' months')
            || DECODE(SUBSTR(b.classInfo, INSTR(b.classInfo,':', 1, 2) + 1, 1),
                'S', ' from the start of the prior run',
                'C', ' from the completion of the prior run')
        WHEN b.classType = 'S' THEN
            NVL2(d.dates, 'Dates: ' || d.dates, NULL)
            || DECODE(SUBSTR(b.classInfo, 32, 1), '1', 'Last day of month ')
            || NVL(
                DECODE(SUBSTR(b.classInfo, 33, 7),
                    '1111111', 'Daily',
                    '0111110', 'Every weekday',
                    NULL),
                DECODE(SIGN(INSTR(SUBSTR(b.classInfo, 33, 7), '1')), 1,
                    'Days of week: '
                    || DECODE(SUBSTR(b.classInfo, 33, 1), '1', 'Su ')
                    || DECODE(SUBSTR(b.classInfo, 34, 1), '1', 'Mo ')
                    || DECODE(SUBSTR(b.classInfo, 35, 1), '1', 'Tu ')
                    || DECODE(SUBSTR(b.classInfo, 36, 1), '1', 'We ')
                    || DECODE(SUBSTR(b.classInfo, 37, 1), '1', 'Th ')
                    || DECODE(SUBSTR(b.classInfo, 38, 1), '1', 'Fr ')
                    || DECODE(SUBSTR(b.classInfo, 39, 1), '1', 'Sa ')
                )
            )
            || DECODE(SUBSTR(b.classInfo, 40, 5),
                '00000', NULL, '11111', NULL, NULL, NULL,
                'Weeks: '
                || DECODE(SUBSTR(b.classInfo, 40, 1), '1', '1st ')
                || DECODE(SUBSTR(b.classInfo, 41, 1), '1', '2nd ')
                || DECODE(SUBSTR(b.classInfo, 42, 1), '1', '3rd ')
                || DECODE(SUBSTR(b.classInfo, 43, 1), '1', '4th ')
                || DECODE(SUBSTR(b.classInfo, 44, 1), '1', '5th ')
            )
            || NVL(
                DECODE(SUBSTR(b.classInfo, 45, 12), '111111111111', ', Every Month'),
                DECODE(SIGN(INSTR(SUBSTR(b.classInfo, 45, 12), '1')), 1,
                    'in ' || TRIM(BOTH ' ' FROM
                        DECODE(SUBSTR(b.classInfo, 45, 1), '1', 'Jan ', '')
                        || DECODE(SUBSTR(b.classInfo, 46, 1), '1', 'Feb ', '')
                        || DECODE(SUBSTR(b.classInfo, 47, 1), '1', 'Mar ', '')
                        || DECODE(SUBSTR(b.classInfo, 48, 1), '1', 'Apr ', '')
                        || DECODE(SUBSTR(b.classInfo, 49, 1), '1', 'May ', '')
                        || DECODE(SUBSTR(b.classInfo, 50, 1), '1', 'Jun ', '')
                        || DECODE(SUBSTR(b.classInfo, 51, 1), '1', 'Jul ', '')
                        || DECODE(SUBSTR(b.classInfo, 52, 1), '1', 'Aug ', '')
                        || DECODE(SUBSTR(b.classInfo, 53, 1), '1', 'Sep ', '')
                        || DECODE(SUBSTR(b.classInfo, 54, 1), '1', 'Oct ', '')
                        || DECODE(SUBSTR(b.classInfo, 55, 1), '1', 'Nov ', '')
                        || DECODE(SUBSTR(b.classInfo, 56, 1), '1', 'Dec ', '')
                    ) || '.',
                ', Every Month')
            )
    END AS schedule
FROM
    base b
    LEFT JOIN dates d ON d.requestId = b.requestId
ORDER BY b.description;