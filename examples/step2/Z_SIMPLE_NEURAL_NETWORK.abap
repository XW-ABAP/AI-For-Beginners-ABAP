*&---------------------------------------------------------------------*
*& Report Z_SIMPLE_NEURAL_NETWORK
*&---------------------------------------------------------------------*
 
REPORT z_simple_neural_network.

" Type definitions for weights and training samples
TYPES: tt_weights TYPE STANDARD TABLE OF f WITH EMPTY KEY.

TYPES: BEGIN OF ty_sample,
         inputs TYPE tt_weights,
         target TYPE f,
       END OF ty_sample,
       tt_samples TYPE STANDARD TABLE OF ty_sample WITH EMPTY KEY.

*----------------------------------------------------------------------*
* CLASS lcl_math DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_math DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS:
      sigmoid IMPORTING iv_x TYPE f RETURNING VALUE(rv_res) TYPE f,
      sigmoid_derivative IMPORTING iv_x TYPE f RETURNING VALUE(rv_res) TYPE f.
ENDCLASS.

CLASS lcl_math IMPLEMENTATION.
  METHOD sigmoid.
    IF iv_x > 100.
      rv_res = '1.0'.
      RETURN.
    ENDIF.
    IF iv_x < -100.
      rv_res = '0.0'.
      RETURN.
    ENDIF.
    rv_res = 1 / ( 1 + exp( - iv_x ) ).
  ENDMETHOD.

  METHOD sigmoid_derivative.
    rv_res = iv_x * ( 1 - iv_x ).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* CLASS lcl_neuron DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_neuron DEFINITION.
  PUBLIC SECTION.
    METHODS:
      constructor IMPORTING iv_num_inputs TYPE i,
      feedforward IMPORTING it_inputs TYPE tt_weights RETURNING VALUE(rv_output) TYPE f,
      train IMPORTING it_inputs        TYPE tt_weights
                      iv_target        TYPE f
                      iv_learning_rate TYPE f DEFAULT '0.1'
            RETURNING VALUE(rv_error)  TYPE f.

    DATA: mt_weights TYPE tt_weights,
          mv_bias    TYPE f,
          mv_output  TYPE f.
ENDCLASS.

CLASS lcl_neuron IMPLEMENTATION.
  METHOD constructor.
    DATA(lo_rand) = cl_abap_random=>create( ).
    DO iv_num_inputs TIMES.
      " Generate random weights between -1 and 1
*      DATA(lv_w) = CONV f( ( lo_rand->float( ) * 2 ) - 1 ).
      DATA(lv_w) = ( lo_rand->float( ) * 2 ) - 1.
      APPEND lv_w TO mt_weights.
    ENDDO.
    " Generate random bias between -1 and 1
    mv_bias = ( lo_rand->float( ) * 2 ) - 1.
  ENDMETHOD.

  METHOD feedforward.
    DATA(lv_total) = mv_bias.
    LOOP AT it_inputs INTO DATA(lv_input).
      DATA(lv_idx) = sy-tabix.
      READ TABLE mt_weights INDEX lv_idx INTO DATA(lv_weight).
      lv_total = lv_total + ( lv_weight * lv_input ).
    ENDLOOP.
    mv_output = lcl_math=>sigmoid( lv_total ).
    rv_output = mv_output.
  ENDMETHOD.

  METHOD train.
    DATA(lv_error) = iv_target - mv_output.
    DATA(lv_delta) = lv_error * lcl_math=>sigmoid_derivative( mv_output ).

    LOOP AT mt_weights ASSIGNING FIELD-SYMBOL(<lv_w>).
      DATA(lv_idx) = sy-tabix.
      READ TABLE it_inputs INDEX lv_idx INTO DATA(lv_input).
      <lv_w> = <lv_w> + ( iv_learning_rate * lv_delta * lv_input ).
    ENDLOOP.

    mv_bias = mv_bias + ( iv_learning_rate * lv_delta ).
    rv_error = abs( lv_error ).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* CLASS lcl_app DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    WRITE: / '======================================================================'(001).
    WRITE: / 'Simple Neural Network from Scratch (ABAP Version)'(002).
    WRITE: / '======================================================================'(001).
    WRITE: / 'Task: Learn to classify points as above or below the line y = x'(003).
    WRITE: /.

    " Step 1: Generate training data
    WRITE: / 'Generating training data...'(004).
    DATA(lo_rand) = cl_abap_random=>create( ).
    DATA(lt_training_data) = VALUE tt_samples( ).

    DO 100 TIMES.
      DATA(lv_x) = lo_rand->float( ) * 10.
      DATA(lv_y) = lo_rand->float( ) * 10.
      DATA(lv_label) = COND f( WHEN lv_y > lv_x THEN 1 ELSE 0 ).
      APPEND VALUE #( inputs = VALUE #( ( lv_x ) ( lv_y ) ) target = lv_label ) TO lt_training_data.
    ENDDO.
    WRITE: / 'Created 100 training examples.'(005).
    WRITE: /.

    " Step 2: Create neuron
    WRITE: / 'Creating a neuron with 2 inputs (x and y coordinates)...'(006).
    DATA(lo_neuron) = NEW lcl_neuron( 2 ).

    READ TABLE lo_neuron->mt_weights INDEX 1 INTO DATA(w1).
    READ TABLE lo_neuron->mt_weights INDEX 2 INTO DATA(w2).
    WRITE: / |Initial weights: [{ w1 }, { w2 }]|.
    WRITE: / |Initial bias: { lo_neuron->mv_bias }|.
    WRITE: /.

    " Step 3: Train the neuron
    WRITE: / 'Training the neuron...'(007).
    DATA(lv_epochs) = 50.

    DO lv_epochs TIMES.
      DATA(lv_epoch) = sy-index.
      DATA(lv_total_error) = CONV f( 0 ).

      LOOP AT lt_training_data ASSIGNING FIELD-SYMBOL(<ls_sample>).
        lo_neuron->feedforward( <ls_sample>-inputs ).
        DATA(lv_err) = lo_neuron->train( it_inputs        = <ls_sample>-inputs
                                         iv_target        = <ls_sample>-target
                                         iv_learning_rate = '0.1' ).
        lv_total_error = lv_total_error + lv_err.
      ENDLOOP.

      IF lv_epoch MOD 10 = 0.
        DATA(lv_avg_error) = lv_total_error / lines( lt_training_data ).
        WRITE: / |Epoch { lv_epoch }/{ lv_epochs } - Average error: { lv_avg_error }|.
      ENDIF.
    ENDDO.

    WRITE: / 'Training complete!'(008).
    READ TABLE lo_neuron->mt_weights INDEX 1 INTO w1.
    READ TABLE lo_neuron->mt_weights INDEX 2 INTO w2.
    WRITE: / |Final weights: [{ w1 }, { w2 }]|.
    WRITE: / |Final bias: { lo_neuron->mv_bias }|.
    WRITE: /.

    " Step 4: Test and Visualize Decision
    WRITE: / 'Testing the trained neuron:'(009).
    WRITE: / '----------------------------------------------------------------------'.
    WRITE: / 'Point          | Prediction    | Actual     | Correct?   '.
    WRITE: / '----------------------------------------------------------------------'.

    DATA(lv_correct) = 0.
    DATA(lv_tests)   = 10.
    DO lv_tests TIMES.
      DATA(lv_tx)        = lo_rand->float( ) * 10.
      DATA(lv_ty)        = lo_rand->float( ) * 10.
      DATA(lv_actual)    = COND f( WHEN lv_ty > lv_tx THEN 1 ELSE 0 ).

      DATA(lv_pred)      = lo_neuron->feedforward( VALUE #( ( lv_tx ) ( lv_ty ) ) ).
      DATA(lv_pred_class) = COND i( WHEN lv_pred > '0.5' THEN 1 ELSE 0 ).
      DATA(lv_act_class)  = CONV i( lv_actual ).
      DATA(lv_status)     = COND string( WHEN lv_pred_class = lv_act_class THEN '✓' ELSE '✗' ).

      IF lv_pred_class = lv_act_class.
        lv_correct = lv_correct + 1.
      ENDIF.

      WRITE: / |({ lv_tx }, { lv_ty }) |
               && |{ lv_pred WIDTH = 15 } |
               && |{ lv_act_class WIDTH = 12 } |
               && |{ lv_status WIDTH = 10 }|.
    ENDDO.

    WRITE: / '----------------------------------------------------------------------'.
    DATA(lv_acc) = ( CONV f( lv_correct ) / lv_tests ) * 100.
    WRITE: / |Accuracy: { lv_acc }% ({ lv_correct }/{ lv_tests } correct)|.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Program Execution Entry
*&---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_app=>run( ).