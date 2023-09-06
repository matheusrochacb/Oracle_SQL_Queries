SELECT 
      isc.CHECKRUN_NAME,
      TO_CHAR(isc.CHECK_DATE, 'mm/dd/yyyy') check_date,
      isc.STATUS batch_status,
      si.INVOICE_NUM,
      si.VENDOR_NUM,
      si.VENDOR_NAME,
      TO_CHAR(si.invoice_date,'mm/dd/yyyy') invoice_date,
      TO_CHAR(si.due_date,'mm/dd/yyyy') due_date,
      ai.INVOICE_AMOUNT,
      nvl(ai.INVOICE_AMOUNT,0) - nvl(ai.AMOUNT_PAID,0) unpaid_amount,
      si.DISCOUNT_AMOUNT discount_amount,
      (nvl(ai.INVOICE_AMOUNT,0) - 
          nvl(ai.AMOUNT_PAID,0)) - 
          si.DISCOUNT_AMOUNT net_amount,
      ipmtl.PAYMENT_METHOD_NAME payment_method,
      ai.DESCRIPTION,
      ai.PAY_GROUP_LOOKUP_CODE pay_group_code,
      flv.MEANING pay_group,
      at.NAME payment_terms,
      (SELECT gcc.SEGMENT2
       FROM AP_INVOICE_DISTRIBUTIONS_ALL  ida,
            GL_CODE_COMBINATIONS          gcc 
       WHERE  gcc.code_combination_id = ida.DIST_CODE_COMBINATION_ID
       AND    ida.INVOICE_ID = ai.INVOICE_ID 
       AND    ida.INVOICE_LINE_NUMBER = ( SELECT MIN(ida2.INVOICE_LINE_NUMBER)
                                          FROM   AP_INVOICE_DISTRIBUTIONS_ALL ida2
                                          WHERE  ida2.INVOICE_ID = ai.INVOICE_ID)  
       AND ROWNUM = 1                                          
      ) Location,
      si.OK_TO_PAY_FLAG ok_to_pay
FROM AP_INV_SELECTION_CRITERIA_ALL isc
  JOIN AP_SELECTED_INVOICES_ALL    si ON si.CHECKRUN_ID = isc.CHECKRUN_ID AND si.OK_TO_PAY_FLAG = 'Y'
  JOIN AP_INVOICES_ALL             ai ON ai.INVOICE_ID = si.INVOICE_ID
  LEFT JOIN FND_LOOKUP_VALUES_VL        flv ON flv.LOOKUP_TYPE = 'PAY GROUP' AND flv.LOOKUP_CODE = ai.PAY_GROUP_LOOKUP_CODE
  LEFT JOIN AP_TERMS_VL                 at ON at.TERM_ID = ai.TERMS_ID
  LEFT JOIN IBY_PAYMENT_METHODS_VL     ipmtl ON ipmtl.PAYMENT_METHOD_CODE = ai.PAYMENT_METHOD_CODE  
WHERE 1=1
AND isc.checkrun_name IN (:p_checkrun_name)
AND (si.VENDOR_NAME IN (:p_supplier_name) OR 'All' IN (:p_supplier_name || 'All'))
ORDER BY isc.checkrun_name, ai.INVOICE_NUM