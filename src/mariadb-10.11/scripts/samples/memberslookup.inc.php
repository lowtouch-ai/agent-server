<?php 

add_action('wp_ajax_ambulanceMembersChecker' , 'amb_member_lookup');
add_action('wp_ajax_no_priv_ambulanceMembersChecker' , 'amb_member_lookup');



function amb_member_lookup(){
	
	header('Content-Type: application/json');

	GLOBAL $mydb;

	$return = ['status' => 'failed' ,'message' => 'Sorry we can not process your request at the moment'];



	if(isset($_POST['member_id']) && isset($_POST['DOB']) && !empty($_POST['member_id']) && !empty($_POST['DOB'])){

		$dob = $_POST['DOB'];
		
		$exp_date = explode('/' , $dob);
		$memberid = (is_numeric($_POST['member_id'])) ? $_POST['member_id'] : false ;
		if(checkdate($exp_date[0], $exp_date[1], $exp_date[2]) === true && $memberid !== false ){
			//Reformat the date of birth to match the database format
			$newdob = date("Y-m-d", strtotime($dob));


			//it is safe to check the member from the database. 
			$member = $mydb->get_results("select * from members_test WHERE id='$memberid' AND DOB='$newdob' LIMIT 1");

			if(empty($member)){
				$return = ['status' => 'failed' , 'message' => 'Member does not match, please check the information and try again.' ];	
			}else{
				//Valid Member
				//
				$return = array('status' => 'success' , 'memberid' => $member[0]->id , 'firstName' => $member[0]->firstName , 'lastName' => $member[0]->lastName , 'DOB' => $dob);
			}

			// $return = ['member' => $member ];
		}else{
			$return = ['status' => 'failed' , 'message' => 'Please insert valid Member id and Date of Birth' ];
		}//Not valid Date	
		
	}else{
		$return = ['status' => 'failed' , 'message' => 'Please insert valid Member id and Date of Birth' ];
	}//Did not post member id and date of birth.
	
	echo json_encode($return);

	die();

}