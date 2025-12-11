<?php

/**
 * This is the function that is responsible for all of the connections will be connecting the gravity forms to the external database connection from the jQuery prespective
 */


function databaselookupfunc_jQuery(){

//Get all required connections.
$args = array(
	"posts_per_page"   => 100,
	"paged"            => 1,
	"orderby"          => "post_date",
	"order"            => "DESC",
	"post_type"        => "gw_gravity_forms",
	"post_status"      => "publish"
);

$connections = get_posts($args); 
?>
<script type="text/javascript">
	$ = jQuery;
	$(function(){
		$('.datepicker').datepicker({
				yearRange: "-100:+0", 
				dateFormat: 'yy-mm-dd' ,
				changeMonth: true,
      			changeYear: true 
			});
			$(".datepicker").attr("autocomplete", "off");
			$()
	});
	<?php 

		foreach($connections as $connector):
			wp_reset_postdata();
			$form_id_to_start = get_field('form_id_to_start' , $connector->ID);
			$table_that_will_start_the_form_looking_up = get_field('table_that_will_start_the_form_looking_up' , $connector->ID);





			//Hide the start form submit button
			?>$('#gform_submit_button_<?php echo $form_id_to_start;  ?>').hide();<?php


			//Insert the loader div.
			?>$('<div id="loader"></div>').insertAfter('#gform_submit_button_<?php echo $form_id_to_start;  ?>');<?php


			//Set the required inputs to be filled to be read only. 
			if (get_field('inputs_to_be_filled' , $connector->ID)) : 
				while(the_repeater_field('inputs_to_be_filled' , $connector->ID)):
					?>$('#<?php  echo get_sub_field('gravity_form_field_id', $connector->ID); ?>').prop("readonly", true);<?php 
			endwhile; 
			endif;



			//Inputs to be gathered 
			

			?>$(document).on('change' , '<?php 


				if (get_field('fields_need_to_be_filled_to_start_the_process' , $connector->ID)) : 
				$counter = 1; 
				$blurString = '';
				while(the_repeater_field('fields_need_to_be_filled_to_start_the_process' , $connector->ID)):
					
					$blurString .= '#gform_' . $form_id_to_start  . ' #'  . get_sub_field('form_input_id', $connector->ID) . ', ' ;
					$counter++;
				endwhile; 
						$blurString = substr($blurString , 0 , -2);
						print $blurString;
				endif;





			?>' , function(){ <?php 

			//Gather the required inputs
			if (get_field('fields_need_to_be_filled_to_start_the_process' , $connector->ID)) : 
				$counter = 1; 
				while(the_repeater_field('fields_need_to_be_filled_to_start_the_process' , $connector->ID)):
					?>input_<?php echo $counter; ?> = $('#gform_<?php echo $form_id_to_start  ?> #<?php echo get_sub_field('form_input_id', $connector->ID);  ?>');<?php
					$counter++;
			endwhile; 
			endif;

			?>

			if(<?php 


				$ifString = '';



				for($i=1; $i<$counter; $i++): $ifString .= 'input_' . $i . '.val() !=="" && '; endfor;  


					$ifString = substr($ifString , 0 , -3);

				echo $ifString;



			?>){
				$('#loader').html('<img src="<?php echo get_template_directory_uri(); ?>/assets/images/loader.gif" width="100px" height="100px" />');


				<?php $url_admin = admin_url(); ?>

				$.post('/nhpri_progress/wp-admin/admin-ajax.php' , {'action': 'gf_db_lookup_ajax' , 'form_sender_id' : <?php print  $form_id_to_start ?> , 

				<?php 

				$ajaxSendingStr = '';
				for($i = 1 ; $i< $counter ; $i++):
					$ajaxSendingStr .= "'input_$i': input_$i.val() , ";

				endfor;

				$ajaxSendingStr = substr($ajaxSendingStr , 0 , -2 );

				print $ajaxSendingStr;


				?>



				 } , function(response){
				if(response.status == 'success'){
					console.log(response);
					$('#loader').html('');
					<?php 

					if (get_field('inputs_to_be_filled' , $connector->ID)) : 
						$counter = 1; 
						$query = '';
						while(the_repeater_field('inputs_to_be_filled' , $connector->ID)):
							

							// $returnValue = '';

							// foreach($sql[0] as $key => $item){
							// 	if($key == get_sub_field('table_field_that_has_data', $connection->ID)){
							// 		$returnValue = $item;
							// 		break;
							// 	}//if $key equal to the requested table field.
							// }//End Foreach

							// $return[get_sub_field('table_field_that_has_data', $connection->ID)] = $returnValue ;
							// $counter++;
							?>
							$('#<?php print get_sub_field('gravity_form_field_id', $connector->ID); ?>').val(response.<?php print get_sub_field('table_field_that_has_data', $connector->ID);  ?>);
							<?php 
						endwhile; 
					endif;

				?>


				}else{
					// console.log(response);
					$('#loader').html('<div class="alert alert-danger">' + response.message + '</div>');
					// alert(response.message);
				}
				
			});



			}

			});<?php



		endforeach;//Foreach each connector 

	?>
</script>
<?php
}


/**
 * This is the function that will be responsible for all of the database lookups in the external databases from the ajax prespective ( server prespective )
 * @return [json] [All the requested fields from the database connection]
 */
function gw_gf_db_lookups(){
	
	header('Content-Type: application/json');
	//This is the extra database connection coming from the ajax init.php file
	GLOBAL $mydb;

	$return = ['status' => 'failed' ,'message' => 'Sorry we can not process your request at the moment'];


	//We are sure that the form id is valid int
	if(isset($_POST['form_sender_id']) && (int) $_POST['form_sender_id'] != 0 ){
		$form_sender_id = (int) $_POST['form_sender_id'];


		//Loop through all of the connections again. 
		
		//Get all required connections.
		$args = array(
			"posts_per_page"   => 100,
			"paged"            => 1,
			"orderby"          => "post_date",
			"order"            => "DESC",
			"post_type"        => "gw_gravity_forms",
			"post_status"      => "publish"
		);

		$connections = get_posts($args); 


		//Loop through the connections
			
			foreach($connections as $connection):
				//match the form id with the form id coming from the jquery request. 
				$form_sender_id_from_db = get_field('form_id_to_start' , $connection->ID);
				//only Apply the code if the form is equal to the sender id form
				if($form_sender_id_from_db == $form_sender_id):

					
						//Table that we will search in.
						$table_name = get_field('database_table_name' , $connection->ID);

					if (get_field('fields_need_to_be_filled_to_start_the_process' , $connection->ID)) : 
						$counter = 1; 
						$query = '';
						while(the_repeater_field('fields_need_to_be_filled_to_start_the_process' , $connection->ID)):
							$query .= ' dbo.' . $table_name . '.'  . get_sub_field('matching_table_field', $connection->ID) . ' LIKE \'%' . $_POST['input_' . $counter ] .'%\' AND ';
							$counter++;
						endwhile; 
					endif;
							$query = substr($query , 0 , -5);
						

							// $sql = $mydb->get_results("select * from $table_name WHERE $query LIMIT 1");

							// $sql_query = "SELECT * FROM members";

							$sql_query = "SELECT TOP 1000 * FROM dbo.$table_name WHERE $query";
     

							$sql_con = sqlsrv_query( $mydb, $sql_query );
							
							$sql = sqlsrv_fetch_array($sql_con);
							
							if(empty($sql)){
								$return = ['status' => 'failed' , 'message' => 'No records matching. Please check your details above.' , 'sql' => $sql_query ];	
							}else{
								//Valid record
								
								$return = array('status' => 'success');
									if (get_field('inputs_to_be_filled' , $connection->ID)) : 
										$counter = 1; 
										$query = '';
										while(the_repeater_field('inputs_to_be_filled' , $connection->ID)):
											

											$returnValue = '';
											
											foreach($sql as $key => $item){
												if($key == get_sub_field('table_field_that_has_data', $connection->ID)){
													// $returnValue = $item;
													//break;
													// $return[get_sub_field('table_field_that_has_data', $connection->ID)] = $item ;
													
													if(is_object( $sql[get_sub_field('table_field_that_has_data', $connection->ID)] )){
														$return[get_sub_field('table_field_that_has_data', $connection->ID)]= date_format($sql[get_sub_field('table_field_that_has_data', $connection->ID)],"Y-m-d "); 
													}else{
														$return[get_sub_field('table_field_that_has_data', $connection->ID)]= $sql[get_sub_field('table_field_that_has_data', $connection->ID)];
													}
													break;
												}//if $key equal to the requested table field.
											}//End Foreach

											
											$counter++;
										endwhile; 
									endif;

							} 

				endif;


			endforeach;//End foreach connection


		//Check all the required inputs that they are not empty
		//Select required table fields from the database
		//If nothing found return string showing that nothing found in the database
		//If Row is found return the requested columns






		
		// $return = ['status' => 'failed' ,'message' => 'Form id is ' . $form_sender_id];	
	}







	// if(isset($_POST['member_id']) && isset($_POST['DOB']) && !empty($_POST['member_id']) && !empty($_POST['DOB'])){

	// 	$dob = $_POST['DOB'];
		
	// 	$exp_date = explode('/' , $dob);
	// 	$memberid = (is_numeric($_POST['member_id'])) ? $_POST['member_id'] : false ;
	// 	if(checkdate($exp_date[0], $exp_date[1], $exp_date[2]) === true && $memberid !== false ){
	// 		//Reformat the date of birth to match the database format
	// 		$newdob = date("Y-m-d", strtotime($dob));


	// 		//it is safe to check the member from the database. 
	// 		$member = $mydb->get_results("select * from members_test WHERE id='$memberid' AND DOB='$newdob' LIMIT 1");

	// 		if(empty($member)){
	// 			$return = ['status' => 'failed' , 'message' => 'Member does not match, please check the information and try again.' ];	
	// 		}else{
	// 			//Valid Member
	// 			//
	// 			$return = array('status' => 'success' , 'memberid' => $member[0]->id , 'firstName' => $member[0]->firstName , 'lastName' => $member[0]->lastName , 'DOB' => $dob);
	// 		}

	// 		// $return = ['member' => $member ];
	// 	}else{
	// 		$return = ['status' => 'failed' , 'message' => 'Please insert valid Member id and Date of Birth' ];
	// 	}//Not valid Date	
		
	// }else{
	// 	$return = ['status' => 'failed' , 'message' => 'Please insert valid Member id and Date of Birth' ];
	// }//Did not post member id and date of birth.
	
	echo json_encode($return);

	die();

}










add_action('wp_footer', 'databaselookupfunc_jQuery');
add_action('wp_ajax_gf_db_lookup_ajax' , 'gw_gf_db_lookups');
add_action('wp_ajax_no_priv_gf_db_lookup_ajax' , 'gw_gf_db_lookups');
