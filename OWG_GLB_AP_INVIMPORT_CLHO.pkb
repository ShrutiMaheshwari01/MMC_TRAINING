create or replace PACKAGE BODY      owg_glb_ap_invimport_clho
IS
  /* $Header: owg_glb_ap_invimport_clho.pkb 1.0 2018/09/25 07:26:36 jithae $ */
  --========================================================================
  -- PROCEDURE : owg_glb_ap_invimport_clho
  -- PARAMETERS:
  -- COMMENT   : To populate data into AP interface table for Beatrice project
  -- PRE-COND  : Data should be available in staging table owg_clho_ap_inv_trxns
  -- EXCEPTIONS: NONE
  -- History
  --  2018/09/25 Jitha Easo       Initial Version -- CCL3565
  -- 2019/04/15 Jitha Easo        Corrected update statement - CCL3617
  -- 2019/05/03 Madhav S         Added Single Instance Project Chanegs CCL3619
  -- 2020/02/24 Rama B          Modified the program to handle SFTP issue - Added new parameters  24 Feb 2020 Jira RELEASE-90
  -- 2022/01/18 Shruti M          Modified code to incorporate changes from CONS to MMC and Italy related changes (Release - 2383)
 -- 2022/01/24 shruti m          added by shm and rm
-- 2022/01/25 shruti m          added by gm
-- 2022/01/25 gm            added by shruti
  --========================================================================
  PROCEDURE load_invoice(
      errbuf       IN OUT VARCHAR2,
      retcode      IN OUT VARCHAR2,
      p_period     VARCHAR2,
      p_file_transfer_command VARCHAR2,  -- Created for SFTP JIRA REL 90
      p_local_path  VARCHAR2                   -- Created for SFTP JIRA REL 90
     -- p_sftp_server VARCHAR2                    -- Created for SFTP JIRA REL 90 --Commented the parameter by Shruti M
    )
IS

l_trf_command       varchar2(240);      -- Created for SFTP JIRA REL 90
l_local_path           varchar2(240);       -- Created for SFTP JIRA REL 90
l_sftp_server          varchar2(240);       -- Created for SFTP JIRA REL 90

CURSOR val_rec(p_period_name VARCHAR2)
IS
 SELECT
        bill_from,
        invoice_num,
        invoice_date,
        currency_code,
        amount,
        dist_seg1,
        dist_seg2,
        dist_seg3,
        dist_seg4,
        dist_seg5,
        dist_seg6,
        owner_entity,
        performer_entity,
        project_code,
        org_id,
        attribute1,
        attribute2,
        attribute3,
        attribute4,
        attribute5,
        period_name,
        vendor_name,
        supplier_number vendor_num,
        vendor_site_code,
        CASE WHEN amount <0 THEN 'CREDIT'
             ELSE 'STANDARD'
        END invoice_type_lookup_code
   FROM owg_clho_ap_inv_trxns  temp
  WHERE status = 'N'
    AND amount <> 0
    AND period_name = p_period_name
    AND NOT EXISTS (SELECT FFV.FLEX_VALUE
                  FROM fnd_flex_value_sets ffvs ,
                       fnd_flex_values_vl ffv
                  WHERE ffvs.flex_value_set_id = FFV.FLEX_VALUE_SET_ID
                  AND flex_value_set_name      = 'MMC_GLB_SI_COUNTRIES'
                  AND SUBSTR(dist_seg1,1,2)    = FFV.FLEX_VALUE
                  AND ffv.enabled_flag         = 'Y'
                  AND TRUNC (SYSDATE) BETWEEN TRUNC ( NVL ( ffv.start_date_active ,SYSDATE)) AND TRUNC ( NVL ( FFV.END_DATE_ACTIVE ,SYSDATE + 1)))
;
CURSOR val_rec_si(p_period_name VARCHAR2)
IS
 SELECT
        bill_from,
        invoice_num,
        invoice_date,
        currency_code,
        amount,
        dist_seg1,
        dist_seg2,
        dist_seg3,
        dist_seg4,
        dist_seg5,
        dist_seg6,
        owner_entity,
        performer_entity,
        project_code,
        org_id,
        attribute1,
        attribute2,
        attribute3,
        attribute4,
        attribute5,
        period_name,
        vendor_name,
        supplier_number vendor_num,
        vendor_site_code,
        CASE WHEN amount <0 THEN 'CREDIT'
             ELSE 'STANDARD'
        END invoice_type_lookup_code
   FROM owg_clho_ap_inv_trxns  temp
  WHERE status = 'N'
    AND amount <> 0
    AND period_name = p_period_name
    AND EXISTS (SELECT FFV.FLEX_VALUE
                  FROM fnd_flex_value_sets ffvs ,
                       fnd_flex_values_vl ffv
                  WHERE ffvs.flex_value_set_id = FFV.FLEX_VALUE_SET_ID
                  AND SUBSTR(dist_seg1,1,2)    = FFV.FLEX_VALUE
                  AND flex_value_set_name      = 'MMC_GLB_SI_COUNTRIES'
                  AND ffv.enabled_flag         = 'Y'
                  AND TRUNC (SYSDATE) BETWEEN TRUNC ( NVL ( ffv.start_date_active ,SYSDATE)) AND TRUNC ( NVL ( FFV.END_DATE_ACTIVE ,SYSDATE + 1)));

    CURSOR rel_rec
    IS
    SELECT (HZ_GEO_GET_PUB.get_conc_name(object_id)) object
                                                  FROM  hz_relationships hr
                                                 WHERE 1= 1
                                                   AND hr.object_type='COUNTRY'
                                                   AND subject_type='EU ZONE'
                                                   AND hr.relationship_type = 'TAX'
                                                   AND hr.relationship_code = 'PARENT_OF'
                                                   AND hr.subject_table_name = 'HZ_GEOGRAPHIES'
                                                   AND hr.object_table_name = 'HZ_GEOGRAPHIES'
                                                   AND NOT EXISTS (SELECT 'X'
                                                                     FROM hz_geography_ranges
                                                                    WHERE geography_id = subject_id
                                                                      AND master_ref_geography_id = hr.object_id);


     l_error_cnt              NUMBER;
     lv_error_msg             VARCHAR2 (32767);
     l_request_id             NUMBER;
     l_id_flex_structure_code fnd_id_flex_structures.id_flex_structure_code%TYPE;
     l_application_short_name fnd_application.application_short_name%TYPE;
     l_structure_num          fnd_id_flex_structures.id_flex_num%type;
     l_key_flex_code          VARCHAR2(240);
     l_validation_date        DATE;
     n_segments               NUMBER;
     segments                 APPS.FND_FLEX_EXT.SEGMENTARRAY;
     l_combination_id         NUMBER;
     l_data_set               NUMBER;
     l_return                 BOOLEAN;
     l_message                VARCHAR2(240);
     l_dummy                  VARCHAR2(1);
     l_doc_category           fnd_doc_sequence_categories.code%TYPE;
     l_territory              fnd_territories_tl.territory_short_name%TYPE;
     l_result                 BOOLEAN;
     l_err_cnt_si             NUMBER;
     l_vendor_site_id          NUMBER;
  BEGIN
      l_error_cnt    := 0;
      l_err_cnt_si   := 0;
      lv_error_msg   := NULL;
      l_request_id := fnd_global.conc_request_id;
      l_trf_command := p_file_transfer_command;     -- Created for SFTP JIRA REL 90
      l_local_path       := p_local_path;                    -- Created for SFTP JIRA REL 90
     -- l_sftp_server    := p_sftp_server;                    -- Created for SFTP JIRA REL 90 --Commented by Shruti M
	 

    BEGIN
      UPDATE owg_clho_ap_inv_trxns
         SET status='N',
             request_id = l_request_id
       WHERE status IS NULL
         AND request_id IS NULL
         AND period_name = p_period;
    EXCEPTION
        WHEN OTHERS THEN
        FND_FILE.put_line(FND_FILE.LOG,'Error in updating status of records to New');
    END;


  FOR inv_rec IN val_rec(p_period)
  LOOP
     --l_error_cnt    := 0;
     lv_error_msg   :=NULL;
     l_dummy        :=NULL;
     l_doc_category := NULL;
	 -- Commented by Shruti M to cater Italy changes
      /*BEGIN
            SELECT 'OWG_IT_AUTOFAT'
              INTO l_doc_category
              FROM hr_operating_units hou
             WHERE  1 = 1
               AND hou.name = 'OWG - Italy'
               AND hou.organization_id = inv_rec.org_id;
       EXCEPTION
       WHEN OTHERS THEN
       l_dummy := NULL;
       END;*/


       BEGIN
       IF l_doc_category IS NOT NULL THEN

           SELECT ftt.territory_short_name
             INTO l_territory
             FROM
                  fnd_territories_tl ftt,
                  ap_supplier_sites_all assa,
                  ap_suppliers aps
            WHERE 1=1/*
              AND ftt.territory_short_name IN ( SELECT UPPER(HZ_GEO_GET_PUB.get_conc_name(object_id))
                                                  FROM  hz_relationships hr
                                                 WHERE 1= 1
                                                   AND hr.object_type='COUNTRY'
                                                   AND subject_type='EU ZONE'
                                                   AND hr.relationship_type = 'TAX'
                                                   AND hr.relationship_code = 'PARENT_OF'
                                                   AND hr.subject_table_name = 'HZ_GEOGRAPHIES'
                                                   AND hr.object_table_name = 'HZ_GEOGRAPHIES'
                                                   AND NOT EXISTS (SELECT 'X'
                                                                     FROM hz_geography_ranges
                                                                    WHERE geography_id = subject_id
                                                                      AND master_ref_geography_id = hr.object_id))*/
             AND ftt.language = 'US'
             AND assa.country = ftt.territory_code
             AND TRUNC(NVL(assa.inactive_date,SYSDATE)) >=TRUNC(SYSDATE)
             AND assa.org_id =  inv_rec.org_id
             AND assa.vendor_site_code = inv_rec.vendor_site_code
             AND assa.vendor_id = aps.vendor_id
             AND NVL(aps.enabled_flag,'N')='Y'
             AND TRUNC(SYSDATE) BETWEEN TRUNC(NVL(aps.start_date_active,SYSDATE)) AND TRUNC(NVL(aps.end_date_active,SYSDATE))
             AND aps.segment1 = inv_rec.vendor_num
             AND rownum = 1;

             FOR cur_rel IN rel_rec LOOP

             IF l_territory = cur_rel.object THEN
                l_doc_category := 'OWG_IT_UE';
                EXIT;
             END IF;
             END LOOP;

       END IF;

    EXCEPTION
        WHEN OTHERS THEN
        FND_FILE.put_line(FND_FILE.LOG,'Error in updating status of records to New');
    END;

      --To find the CCIS
      BEGIN
            SELECT  c.id_flex_structure_code
              INTO l_id_flex_structure_code
              FROM fnd_id_flex_structures_vl c,
                   fnd_id_flex_segments_vl g,
                   fnd_flex_values_vl v,
                   gl_ledgers s,
                   hr_operating_units hou
             WHERE c.id_flex_code = 'GL#'
               AND s.ledger_id = hou.set_of_books_id
               AND hou.organization_id = inv_rec.org_id
               AND s.chart_of_accounts_id = c.id_flex_num
               AND c.id_flex_code = g.id_flex_code
               AND c.id_flex_num = g.id_flex_num
               AND g.application_column_name = ('SEGMENT1')
               AND g.flex_value_set_id = v.flex_value_set_id
               AND v.enabled_flag = 'Y'
--               AND v.flex_value = inv_rec.revenue_seg1
             GROUP BY c.id_flex_structure_code;

      l_application_short_name := 'SQLGL';
      l_key_flex_code          := 'GL#';
      l_validation_date        := SYSDATE;
      n_segments               := 5;
      segments(1)              := inv_rec.dist_seg1;
      segments(2)              := inv_rec.dist_seg2;
      segments(3)              := inv_rec.dist_seg3;
      segments(4)              := inv_rec.dist_seg4 ;
      segments(5)              := inv_rec.dist_seg5;
      l_data_set               := NULL;

        BEGIN
          SELECT id_flex_num
            INTO l_structure_num
            FROM apps.fnd_id_flex_structures
           WHERE id_flex_code = 'GL#'
             AND id_flex_structure_code = l_id_flex_structure_code;

          l_return := FND_FLEX_EXT.GET_COMBINATION_ID(
                    application_short_name => l_application_short_name,
                    key_flex_code          => l_key_flex_code,
                    structure_number       => l_structure_num,
                    validation_date        => l_validation_date,
                    n_segments             => n_segments,
                    segments               => segments,
                    combination_id         => l_combination_id,
                    data_set               => l_data_set
                    );
          l_message:= FND_FLEX_EXT.GET_MESSAGE;

          IF l_return THEN
            NULL;
          ELSE
            lv_error_msg      := lv_error_msg || '; Invalid CCID'||SQLERRM;
            FND_FILE.put_line(FND_FILE.LOG,'Error Message: '||'Invalid CCID: '||inv_rec.dist_seg1||'-'||inv_rec.dist_seg2||'-'||inv_rec.dist_seg3||'-'||inv_rec.dist_seg4||'-'||inv_rec.dist_seg5);
            --l_error_cnt       := l_error_cnt + 1;
          END IF;

        EXCEPTION
          WHEN OTHERS THEN
             lv_error_msg      := lv_error_msg || '; Not able to find the Flexfield Structure'||SQLERRM;
             FND_FILE.put_line(FND_FILE.LOG,'Not able to find the Flexfield Structure'||SQLERRM);
           --  l_error_cnt       := l_error_cnt + 1;
        END;

      EXCEPTION
        WHEN OTHERS THEN
               lv_error_msg    := lv_error_msg || '; Not able to find the Accounting Flexfield'||SQLERRM;
               FND_FILE.put_line(FND_FILE.LOG,'Not able to find the Accounting Flexfield'||SQLERRM);
           --    l_error_cnt     := l_error_cnt + 1;
      END;

     /* FND_FILE.put_line(FND_FILE.LOG,'Error Count: '||l_error_cnt);
      FND_FILE.put_line(FND_FILE.LOG,'Error Message: '||lv_error_msg);    */
      --FND_FILE.put_line(FND_FILE.LOG,'Inserting successfully validated record into Interface table');
      BEGIN

               INSERT INTO ap_invoices_interface (invoice_id,
                                                      org_id,
                                                      source,
                                                      invoice_date,
                                                      gl_date,
                                                      invoice_currency_code,
                                                      invoice_amount,
                                                      exchange_rate_type,
                                                      invoice_num,
                                                      vendor_name,
                                                      vendor_num,
                                                      vendor_site_code, 
                                                      description,
                                                      invoice_type_lookup_code,
                                                      calc_tax_during_import_flag,
                                                      add_tax_to_inv_amt_flag,
                                                      doc_category_code,
                                                      group_id,
                                                      creation_date,
                                                      created_by,
                                                      last_update_date,
                                                      last_updated_by,
                                                      last_update_login
                                                      )
                                              VALUES (   ap_invoices_interface_s.NEXTVAL, --invoice_id
                                                         inv_rec.org_id, --org_id
                                                         'OWG TEAM ICO', -- ,source
                                                         inv_rec.invoice_date,--invoice_date,
                                                         inv_rec.invoice_date,--gl_date,
                                                         inv_rec.currency_code, --invoice_currency_code
                                                         inv_rec.amount,--invoice_amount,
                                                         'Corporate',--exchange_rate_type,
                                                         inv_rec.invoice_num, --invoice_num
                                                         inv_rec.vendor_name,  --vendor_name
                                                         inv_rec.vendor_num, --vendor_num
                                                         inv_rec.vendor_site_code,
                                                         'OWG IO Invoice', --description
                                                         inv_rec.invoice_type_lookup_code,
                                                         'Y', --calc_tax_during_import_flag
                                                         'Y', --add_tax_to_inv_amt_flag
                                                         l_doc_category,
                                                         inv_rec.vendor_num, --group_id
                                                         SYSDATE,
                                                         fnd_global.user_id,
                                                         SYSDATE,
                                                         fnd_global.user_id,
                                                         fnd_global.login_id
                                                         );

           INSERT INTO ap.ap_invoice_lines_interface( invoice_id,
                                                      invoice_line_id,
                                                      line_number,
                                                      line_type_lookup_code,
                                                      quantity_invoiced,
                                                      unit_price,
                                                      amount,
                                                      accounting_date,
                                                      dist_code_combination_id,
                                                      dist_code_concatenated,
                                                      attribute_category,
                                                      attribute10,
                                                      attribute11,
                                                      attribute12,
                                                      attribute13,
                                                      attribute14,
                                                      creation_date,
                                                      created_by,
                                                      last_update_date,
                                                      last_updated_by,
                                                      last_update_login
                                                      )
                                               VALUES(   ap_invoices_interface_s.CURRVAL,  --invoice_id
                                                         ap_invoice_lines_interface_s.NEXTVAL, --invoice_line_id
                                                         1,  --line_number
                                                         'ITEM', --line_type_lookup_code
                                                         1, --quantity_invoiced
                                                         inv_rec.amount, --unit_price
                                                         inv_rec.amount, --amount
                                                         inv_rec.invoice_date, --accounting_date
                                                         l_combination_id, --dist_code_combination_id
                                                         inv_rec.dist_seg1||'-'||inv_rec.dist_seg2||'-'||inv_rec.dist_seg3||'-'||inv_rec.dist_seg4||'-'||inv_rec.dist_seg5, --dist_code_concatenated
                                                         inv_rec.org_id, --attribute_category
                                                         inv_rec.project_code, --attribute10
                                                         inv_rec.attribute2, --attribute11
                                                         inv_rec.performer_entity, --attribute12
                                                         inv_rec.owner_entity, --attribute13
                                                         inv_rec.attribute1, --attribute14
                                                         SYSDATE,
                                                         fnd_global.user_id,
                                                         SYSDATE,
                                                         fnd_global.user_id,
                                                         fnd_global.login_id
                                                     );
                                BEGIN
                                   UPDATE owg_clho_ap_inv_trxns temp
                                      SET status='S'
                                    WHERE 1 = 1
                                      AND bill_from = inv_rec.bill_from  -- Added CCL3617
                                      AND org_id =  inv_rec.org_id   -- Added CCL3617
                                      AND invoice_num = inv_rec.invoice_num
                                      AND request_id = l_request_id;
                                EXCEPTION
                                WHEN OTHERS THEN
                                FND_FILE.put_line(FND_FILE.LOG,'Error updating staging table data for interface run'||SQLERRM);
                             END;
           EXCEPTION
             WHEN OTHERS THEN
                FND_FILE.put_line(FND_FILE.LOG,'Error inserting into interface table'||SQLERRM);
                l_error_cnt := l_error_cnt + 1;
           END;
  END LOOP;

  IF l_error_cnt <> 0 THEN
      BEGIN
        l_result := fnd_concurrent.set_completion_status('WARNING','Please check the logfile for Exceptions raised by the program');
        COMMIT;
      END;
  END IF;

  ---Added below code for SI Changes by MS on 03052019.

   FOR inv_rec_si IN val_rec_si(p_period)
  LOOP
     lv_error_msg   :=NULL;
     l_dummy        :=NULL;
     l_doc_category := NULL;
      --Commented by Shruti M to cater Italy related changes
       /*BEGIN
            SELECT 'OWG_IT_AUTOFAT'
              INTO l_doc_category
              FROM hr_operating_units hou
             WHERE  1 = 1
               AND hou.name = 'OWG - Italy'
               AND hou.organization_id = inv_rec_si.org_id;
       EXCEPTION
       WHEN OTHERS THEN
       l_dummy := NULL;
       END;*/

       BEGIN
       IF l_doc_category IS NOT NULL THEN

           SELECT ftt.territory_short_name
             INTO l_territory
             FROM
                  fnd_territories_tl ftt,
                  ap_supplier_sites_all assa,
                  ap_suppliers aps
            WHERE 1=1
             AND ftt.language = 'US'
             AND assa.country = ftt.territory_code
             AND TRUNC(NVL(assa.inactive_date,SYSDATE)) >=TRUNC(SYSDATE)
             AND assa.org_id =  inv_rec_si.org_id
             AND assa.vendor_site_code = inv_rec_si.vendor_site_code
             AND assa.vendor_id = aps.vendor_id
             AND NVL(aps.enabled_flag,'N')='Y'
             AND TRUNC(SYSDATE) BETWEEN TRUNC(NVL(aps.start_date_active,SYSDATE)) AND TRUNC(NVL(aps.end_date_active,SYSDATE))
             AND aps.segment1 = inv_rec_si.vendor_num
             AND rownum = 1;

             FOR cur_rel IN rel_rec LOOP

             IF l_territory = cur_rel.object THEN
                l_doc_category := 'OWG_IT_UE';
                EXIT;
             END IF;
             END LOOP;

       END IF;

    EXCEPTION
        WHEN OTHERS THEN
        FND_FILE.put_line(FND_FILE.LOG,'Error in updating status of records to New');
    END;

       BEGIN
               BEGIN
                    SELECT vendor_site_id
                      INTO l_vendor_site_id
                      FROM ap_suppliers            aps,
                           ap_supplier_sites_all   assa
                     WHERE aps.vendor_id = assa.vendor_id
                       AND aps.segment1 = inv_rec_si.vendor_num
                       AND assa.vendor_site_code = inv_rec_si.vendor_site_code
                       AND org_id = inv_rec_si.org_id;
               EXCEPTION
                       WHEN OTHERS THEN
                       l_vendor_site_id := NULL;
               END;

               INSERT INTO MMC_GLB_AP_INVOICE_INT_STG_SI(
                                                        INVOICE_ID                 ,
                                                        INVOICE_NUM                ,
                                                        INVOICE_TYPE_LOOKUP_CODE   ,
                                                        INVOICE_DATE               ,
                                                        VENDOR_NUM                 ,
                                                        VENDOR_NAME                ,
                                                        VENDOR_SITE_ID             ,
                                                        VENDOR_SITE_CODE           , 
                                                        INVOICE_AMOUNT             ,
                                                        INVOICE_CURRENCY_CODE      ,
                                                        EXCHANGE_RATE_TYPE         ,
                                                        DESCRIPTION                ,
                                                        STATUS                     ,
                                                        SOURCE                     ,
                                                        GROUP_ID                   ,
                                                        REQUEST_ID                 ,
                                                        DOC_CATEGORY_CODE          ,
                                                        GL_DATE                    ,
                                                        ORG_ID                     ,
                                                        CALC_TAX_DURING_IMPORT_FLAG,
                                                        ADD_TAX_TO_INV_AMT_FLAG    ,
                                                        INVOICE_LINE_ID            ,
                                                        LINE_NUMBER                ,
                                                        LINE_TYPE_LOOKUP_CODE      ,
                                                        AMOUNT                     ,
                                                        ACCOUNTING_DATE            ,
                                                        QUANTITY_INVOICED          ,
                                                        UNIT_PRICE                 ,
                                                        DIST_CODE_CONCATENATED     ,
                                                        DIST_CODE_COMBINATION_ID   ,
                                                        ATTRIBUTE_CATEGORY         ,
                                                        ATTRIBUTE10                ,
                                                        ATTRIBUTE11                ,
                                                        ATTRIBUTE12                ,
                                                        ATTRIBUTE13                ,
                                                        ATTRIBUTE14                ,
                                                        LAST_UPDATE_DATE           ,
                                                        LAST_UPDATED_BY            ,
                                                        LAST_UPDATE_LOGIN          ,
                                                        CREATION_DATE              ,
                                                        CREATED_BY
                                                        )
                                                VALUES(
                                                        NULL,--ap_invoices_interface_s.NEXTVAL, --Invoice_id
                                                        inv_rec_si.invoice_num,         --invoice_num
                                                        inv_rec_si.invoice_type_lookup_code,
                                                        inv_rec_si.invoice_date,         --invoice_date,
                                                        inv_rec_si.vendor_num,         --vendor_num
                                                        inv_rec_si.vendor_name,          --vendor_name
                                                        l_vendor_site_id,
                                                        inv_rec_si.vendor_site_code,     --vendor_site_code 
                                                        inv_rec_si.amount,             --AMOUNT
                                                        inv_rec_si.currency_code,         --INVOICE_CURRENCY_CODE
                                                        'Corporate',                --exchange_rate_type
                                                        'OWG IO Invoice',             --description
                                                        'X',
                                                        'OWG TEAM ICO',             --source
                                                        inv_rec_si.vendor_num,         --group_id
                                                        l_request_id,
                                                        l_doc_category,
                                                        inv_rec_si.invoice_date,        --gl_date
                                                        inv_rec_si.org_id ,
                                                        'Y',                        --CALC_TAX_DURING_IMPORT_FLAG
                                                        'Y',                         --ADD_TAX_TO_INV_AMT_FLAG
                                                        NULL,                         --ap_invoice_lines_interface_s.NEXTVAL, --invoice_line_id
                                                        1,                          --line_number
                                                        'ITEM',                     --line_type_lookup_code
                                                        inv_rec_si.amount,             --AMOUNT
                                                        inv_rec_si.invoice_date,         --accounting_date
                                                        1,                            --QUANTITY_INVOICED
                                                        inv_rec_si.amount,             --unit_price
                                                        inv_rec_si.dist_seg1||'-'||inv_rec_si.dist_seg2||'-'||inv_rec_si.dist_seg3||'-'||inv_rec_si.dist_seg4||'-'||inv_rec_si.dist_seg5, --dist_code_concatenated     ,
                                                        NULL ,                        --DIST_CODE_COMBINATION_ID
                                                        inv_rec_si.org_id,             --attribute_category
                                                        inv_rec_si.project_code,         --attribute10
                                                        inv_rec_si.attribute2,         --attribute11
                                                        inv_rec_si.performer_entity,     --attribute12
                                                        inv_rec_si.owner_entity,         --attribute13
                                                        inv_rec_si.attribute1,         --attribute14
                                                        SYSDATE,
                                                        fnd_global.user_id,
                                                        fnd_global.login_id,
                                                        SYSDATE,
                                                        fnd_global.user_id
                                                       );
                                BEGIN
                                   UPDATE owg_clho_ap_inv_trxns temp
                                      SET status='S'
                                    WHERE 1 = 1
                                      AND bill_from = inv_rec_si.bill_from
                                      AND invoice_num = inv_rec_si.invoice_num
                                      AND org_id = inv_rec_si.org_id
                                      AND request_id = l_request_id;
                                EXCEPTION
                                WHEN OTHERS THEN
                                FND_FILE.put_line(FND_FILE.LOG,'Error updating staging table data for interface run'||SQLERRM);
                             END;
           EXCEPTION
             WHEN OTHERS THEN
                FND_FILE.put_line(FND_FILE.LOG,'Error inserting into interface table'||SQLERRM);
                l_err_cnt_si := l_err_cnt_si + 1;
           END;
  END LOOP;

    IF l_err_cnt_si <> 0 THEN
      BEGIN
        l_result := fnd_concurrent.set_completion_status('WARNING','Please check the logfile for Exceptions raised by the program');
        COMMIT;
      END;
    END IF;
    OWG_T2GL_CONS_TO_RIS_FTP(
         l_trf_command ,
         l_local_path  );
       --  l_sftp_server ); --Commented Parameter by Shruti M
  --- End of code addition by MS for SI on 02042019.
  END load_invoice;

  --Added by MS for SI on 03May2019 for FTP to RIS CCL3619
Procedure OWG_T2GL_CONS_TO_RIS_FTP
(     p_file_transfer_command VARCHAR2,
      p_local_path  VARCHAR2)
    --  p_sftp_server VARCHAR2) --Commented parameter by Shruti M
	  AS

   lc_phase            VARCHAR2 (20) ;
   lc_status           VARCHAR2 (20) ;
   lc_dev_phase        VARCHAR2 (20) ;
   lc_dev_status       VARCHAR2 (20) ;
   LC_MESSAGE          varchar2 (4000);
   ln_request_id        NUMBER:=0;
   l_req_return_status boolean;
   l_argument2         fnd_descr_flex_col_usage_vl.DEFAULT_VALUE%TYPE;  -- Created for SFTP JIRA REL 90
   l_argument3       fnd_descr_flex_col_usage_vl.DEFAULT_VALUE%TYPE;    -- Created for SFTP JIRA REL 90
   l_argument4       fnd_descr_flex_col_usage_vl.DEFAULT_VALUE%TYPE;    -- Created for SFTP JIRA REL 90
   P_RE_REQUEST_ID   number;
   l_request_id NUMBER := fnd_global.conc_request_id;

   begin
       /*begin
        SELECT fdfcuv.default_value into l_argument2
          FROM fnd_concurrent_programs fcp ,
            fnd_concurrent_programs_tl fcpl ,
            fnd_descr_flex_col_usage_vl fdfcuv ,
            fnd_application_vl fav
          WHERE fcp.concurrent_program_id       = fcpl.concurrent_program_id
          AND fcp.CONCURRENT_PROGRAM_NAME       = 'OWG_GLB_APXLA_CONS2RIS_EXTRACT'
          AND fav.application_id                =fcp.application_id
          AND fcpl.language                     = 'US'
          and fdfcuv.end_user_column_name       = 'File Transfer Command'
          and fdfcuv.descriptive_flexfield_name = '$SRS$.'|| fcp.concurrent_program_name;
         exception
            when no_data_found then
           dbms_output.put_line ('No FTP path found for File Transfer: '|| ln_request_id || ' '|| SQLERRM );
       end;*/


/**  Commented by RB for JIRA-REL-88 to handle SFTP Issue 24 Feb 2020 */
/*
    begin
       select '/opt/oraerp/'||decode(lower(name),'oltd82','oltd72','oltt96','oltt81','oltt97','oltt82','oltp73','oltp71')||'/apps_st/'||decode(lower(name),'oltd82','oltd72','oltt96','oltt81','oltt97','oltt82','oltp73','oltp71')||'appl/conscus/12.0.0/data/beatrice'
       into l_argument2
       from v$database;

       select '/opt/oraerp/'||lower(instance_name)||'/apps_st/'||lower(instance_name)||'appl'||'/conscus/12.0.0/data/beatrice'
       into l_argument3 from v$instance;

       SELECT  decode(code2, 'PROD', 'usdfw31as03','BFX','usfkl32as04','TEST','usdfw33as43','DEV','appld72@usdfw33ld1as02','UAT','usfkl32as03')||'.mmc.com'
       into l_argument4 FROM apps.WMMGD_INTERFACE_FUNCTION a, v$instance WHERE a.CODE1 =upper( instance_name) and a.function_code = 'DATABASE Type' and a.country_code = 'GLOBAL';


       exception
       when others then
       l_argument2 := null;
    end;

*/

/**  Added by RB for JIRA-REL-88 to handle SFTP Issue 24 Feb 2020 */

      l_argument2   := p_file_transfer_command;     -- Created for SFTP JIRA REL 90
      l_argument3   := p_local_path;                        -- Created for SFTP JIRA REL 90
      --l_argument4   := p_sftp_server;                       -- Created for SFTP JIRA REL 90 --Commented parameter by Shruti M

      ln_request_id:=fnd_request.submit_request (application      => 'CONSCUS',
                                                    program       => 'OWG_GLB_APXLA_CONS2RIS_EXTRACT',
                                                    start_time    => SYSDATE,
                                                    sub_request   => false,
                                                    argument1     => l_request_id,
                                                    Argument2     => l_argument2,
                                                    Argument3     => l_argument3
                                                   -- Argument4     => l_argument4 --Commented parameter by Shruti M
                                                   );
   COMMIT;

   IF ln_request_id > 0
   THEN
      LOOP
         --To make process execution to wait for 1st program to complete
         l_req_return_status :=
            fnd_concurrent.wait_for_request
               (request_id      => ln_request_id,
                INTERVAL        => 5, --interval Number of seconds to wait between checks
                max_wait        => 60,--Maximum number of seconds to wait for the request completion
                -- out arguments
                phase           => lc_phase,
                status          => lc_status,
                dev_phase       => lc_dev_phase,
                dev_status      => lc_dev_status,
                MESSAGE         => lc_message
               );
         EXIT WHEN UPPER (lc_phase) = 'COMPLETED'
               OR UPPER (lc_status) IN ('CANCELLED', 'ERROR', 'TERMINATED');
      END LOOP;

      IF UPPER (lc_phase) = 'COMPLETED' AND UPPER (lc_status) = 'ERROR'
      THEN
         DBMS_OUTPUT.put_line
            (   'The OWG_GLB_AP2GL_CONS2RIS_EXTRACT completed in error. Oracle request id: '|| ln_request_id || ' '|| SQLERRM );
      ELSIF UPPER (lc_phase) = 'COMPLETED' AND UPPER (lc_status) = 'NORMAL'
      THEN
         DBMS_OUTPUT.put_line
            (   'The OWG_GLB_AP2GL_CONS2RIS_EXTRACT request successful for request id: ' || ln_request_id);
      ELSE
         DBMS_OUTPUT.put_line
            (   'The OWG_GLB_AP2GL_CONS2RIS_EXTRACT request failed. Oracle request id: '|| ln_request_id || ' '|| SQLERRM);
      END IF;
   end if;
END OWG_T2GL_CONS_TO_RIS_FTP;
END OWG_GLB_AP_INVIMPORT_CLHO;
