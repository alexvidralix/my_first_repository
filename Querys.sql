/*1--select*/

SELECT cu.first_name,
       cu.last_name,
       ca.id,
       ca.card_number,
       ac.account_class_id,
       tr.amount,
       COUNT(tr.amount),
       tr.debit_acc_id,
       tr.credit_acc_id
FROM customers cu
INNER JOIN cards ca ON ca.customer_id = cu.id
INNER JOIN accounts ac ON ac.customer_id = ca.customer_id
INNER JOIN transactions tr ON CASE
                                  WHEN tr.debit_acc_id IS NULL THEN tr.credit_acc_id
                                  ELSE tr.debit_acc_id
                              END = ac.id
INNER JOIN transactions tr ON CASE
                                  WHEN tr.debit_acc_id IS NULL THEN tr.credit_acc_id
                                  ELSE tr.debit_acc_id
                              END = ac.id
WHERE tr.amount >= 10.00
GROUP BY cu.first_name,
         cu.last_name,
         ca.id,
         ca.card_number,
         ac.account_class_id,
         tr.amount,
         tr.debit_acc_id,
         tr.credit_acc_id
HAVING COUNT(tr.amount) >= 10



/*2--select hierarchi*/
SELECT 
t_result.id,
t_result.long_description,
t_result.address,
t_result.parent_branch_id,
tr.amount
FROM
  (SELECT id,
          long_description,
          address,
          parent_branch_id
   FROM Branches START WITH id =2 CONNECT BY
   PRIOR parent_branch_id = id) t_result
LEFT JOIN Transactions tr ON tr.transaction_branch_id = t_result.id



/*3--leaps*/
WITH all_transaction AS
  (SELECT id,
          CASE
              WHEN debit_acc_id IS NULL THEN credit_acc_id
              ELSE debit_acc_id
          END AS cust_id,
          amount,
          inserted_date,
          EXTRACT(YEAR
                  FROM to_date(inserted_date, 'DD-Mon-YYYY HH24:MI:SS')) AS year1
   FROM transactions),
     leap_years AS
  (SELECT CUST_ID,
          MAX(inserted_date),
          CASE
              WHEN
                     (SELECT to_char(last_day(to_date('01-FEB-' || to_char(MAX(year1)), 'DD-MON-YYYY')), 'DD')
                      FROM dual) = 29 THEN 'not ok'
              ELSE 'ok'
          END AS leap_year,
          row_number() over(PARTITION BY max(CUST_ID)
                            ORDER BY max(inserted_date) DESC) rn
   FROM all_transaction
   GROUP BY CUST_ID,
            year1),
     leaps AS
  (SELECT cust_id
   FROM leap_years
   WHERE leap_year = 'ok'
     AND rn =1 )
SELECT a.cust_id,
       a.amount
FROM
  (SELECT cust_id,
          amount,
          DENSE_RANK() OVER (PARTITION BY cust_id
                             ORDER BY amount DESC) AS TRANS_RANK
   FROM all_transaction) A
WHERE A.TRANS_RANK = 2
  AND a.cust_id in
    (SELECT cust_id
     FROM leaps);


/*4--update_cust_details*/


CREATE OR REPLACE PROCEDURE update_cust_details (
    p_id                customers.id%TYPE,
    p_first_name        customers.first_name%TYPE,
    p_last_name         customers.last_name%TYPE,
    p_date_of_birth     customers.date_of_birth%TYPE,
    p_status            customers.status%TYPE,
    p_open_branch_id    customers.open_branch_id%TYPE
) AS
BEGIN
    UPDATE customers
    SET
        first_name = p_first_name,
        last_name = p_last_name,
        date_of_birth = p_date_of_birth,
        status = p_status,
        open_branch_id = p_open_branch_id
    WHERE
        id = p_id;

    COMMIT;
END;


/*5--wrk_days*/

CREATE OR REPLACE FUNCTION wrk_days (
    x INTEGER
) RETURN DATE AS

    n_counter   NUMBER := 0;
    v_dsc       VARCHAR(100);
    sys_day     NUMBER := to_char(sysdate, 'DD');
    start_date  DATE := trunc(sysdate);
    end_date    DATE := start_date;
BEGIN
    WHILE n_counter < x LOOP
        SELECT
            substr((
                SELECT
                    LISTAGG(holiday_list, '') WITHIN GROUP(
                        ORDER BY
                            year, month
                    ) AS dt
                FROM
                    holidays
                WHERE
                        year >= to_char(sysdate, 'YYYY')
                    AND month >= to_char(sysdate, 'MM')
            ),
                   (sys_day + x),
                   1)
        INTO v_dsc
        FROM
            dual;

        n_counter := n_counter + 1;
        end_date := end_date + 1;
    END LOOP;

    IF v_dsc = 'H' THEN
        end_date := end_date + 1;
    END IF;
    RETURN end_date;
END wrk_days;






/*6--trigger*/

CREATE OR REPLACE TRIGGER status_acc BEFORE
    UPDATE ON Accounts
    FOR EACH ROW
BEGIN
    IF  :NEW.available_balance < 0.00
    THEN :NEW.status := 'CLOSED';
    end if;
END;  


/*7--update_accounts*/

CREATE OR REPLACE PROCEDURE update_accounts AS
    v_out VARCHAR2(50) := 'OK';
BEGIN
    MERGE INTO other_accounts e2
    USING accounts h1 ON ( e2.id = h1.id )
    WHEN MATCHED THEN UPDATE
    SET e2.currency = h1.currency,
        e2.available_balance = h1.available_balance,
        e2.status = h1.status,
        e2.inserted_date = h1.inserted_date,
        e2.inserted_by = h1.inserted_date
    WHEN NOT MATCHED THEN
    INSERT (
        id,
        account_number,
        currency,
        iban,
        account_class_id,
        available_balance,
        status,
        customer_id )
    VALUES
        ( h1.id,
          h1.account_number,
          h1.currency,
          h1.iban,
          h1.account_class_id,
          h1.available_balance,
          h1.status,
          h1.customer_id );

    dbms_output.put_line(v_out);
    return;
EXCEPTION
    WHEN OTHERS THEN
        raise_application_error(-20001, 'An error was encountered - '
                                        || sqlcode
                                        || ' -ERROR- '
                                        || sqlerrm);
END;


/*8--update_available_balance*/

CREATE OR REPLACE PROCEDURE update_available_balance AS v_out VARCHAR2(50):='OK';

BEGIN
MERGE INTO Accounts e2 USING
  (WITH trans AS
     (SELECT CASE
                 WHEN debit_acc_id IS NULL THEN credit_acc_id
                 ELSE debit_acc_id
             END AS id1,
             sum(amount) AS amount
      FROM Transactions
      WHERE inserted_date >= trunc(sysdate)-1
        AND inserted_date < trunc(sysdate)
      GROUP BY debit_acc_id,
               credit_acc_id),
        fin AS
     (SELECT id1,
             sum(amount) amount
      FROM trans
      GROUP BY id1)SELECT *
   FROM fin) h1 ON (e2.id = h1.id1) WHEN MATCHED THEN
UPDATE
SET e2.available_balance = e2.available_balance + h1.amount;

DBMS_OUTPUT.put_line(v_out);

RETURN;


EXCEPTION WHEN OTHERS THEN raise_application_error(-20001, 'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);

END;