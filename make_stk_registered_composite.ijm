#@ File(label="Select the first stk file", style="file, extensions:stk") input_file
#@ Float(label="Z spacing (microns)", description="Distance between two consecutive slices. Can be found in the non image files in the folder", value=1) z_resolution  
#@ String (visibility=MESSAGE, value=" ") msg
#@ Integer(label="Number of timepoints (T)", description="Number of time points in your stack", value=27) tp_total_number
#@ Integer(label="Number of slices (Z)", description="Number of slices in your stack", value=161) slice_total_number
#@ Integer(label="First S to process", description="First S to process, start of the loop", value=1) s_start
#@ Integer(label="Number of s (S)", description="Number of X in your experiment", value=2) s_total_number
#@ String(label="Name of the different channels", description="Enter the names corresponding to your channels separated by a comma. For example, if you have Cy5 and DAPI, B09 just enter Cy5,DAPI", value="DAPI,GFP,mCherry,Cy5") channels_sequence
#@ String(label="Name of the channel of reference for the registration", description="Enter the name of the channel used for registration of all slices and channels", value="mCherry") ref_channel

/*
 * @author        Laurent Guerard
 * @group         IMCF
 * @email         laurent.guerard@unibas.ch
 * @date_creation Tue Jan 09 09:19:50 2019
 * @modified      Wed Mar 20 15:40:42 2019
*/

print("\\Clear");

function image_sequence_based_on_regex(channel_to_open, s_to_open, input_file)
{
	// Function to open images based on the current loop(s).
	// Will return the ID of the opened file
	regex = channel_to_open + ".*" + s_to_open + "_";
	run("Image Sequence...", "open=[" + input_file + "] file=("+ regex + ") sort");
	return getImageID();
}

function get_folder_from_file(input_file)
{
	// Returns the path to the file depending on the input_file
	folder = substring(input_file,0,lastIndexOf(input_file,File.separator)+1);
	return folder;
}

/*function find_channel_in_array(channel_to_find, channels_array)
{
	// Find the index for the channel to find in an array
	channels_array_length = lengthOf(channels_array);
	for(i = 0; i < channel_array_length; i++)
	{
		if (channels_array[i] == channel_to_find)
			return i;
	}

	exit("Reference channel not in the channels");
}*/

function delete_temp_files()
{
	// Since MultiStackReg doesn't do it properly
	// Cleans the Temp folder by deleting everyfile inside
	// Avoids C: to be filled.
	tmp_dir = getDirectory("temp");
	list_temp_files = getFileList(tmp_dir);
	for(i=0;i<list_temp_files.length;i++)
		variable_to_hide_output = File.delete(tmp_dir + list_temp_files[i]);
}

channel_array        = split(channels_sequence,",,");
channel_array_length = lengthOf(channel_array);
merge_string         = "";
mid_slice = floor(slice_total_number/2);

setBatchMode(true)
print("Macro started");

tm_var = ""

// Loop through the s
for(j = s_start; j <= s_total_number; j++)
{
	current_s = "s" + j;
	print("\\Update"+j+1+":Working on " + current_s);

	// 1ST STEP
	// GET THE TRANSFORMATION MATRIX FROM MULTISTACKREG
	print("\\Update"+j+2+":Working on channel " + ref_channel + " to make transformation matrix...");

	output_dir    = get_folder_from_file(input_file);
	old_name      = input_file;
	old_name      = substring(old_name,lastIndexOf(old_name,"\\")+1,indexOf(old_name,"_"));
	old_name      = replace(old_name," ","_");
	output_folder = output_dir + old_name + File.separator;
	if(!File.exists(output_folder))
		File.makeDirectory(output_folder); 

	transform_matrix_file = output_folder + "transform_matrix.txt";

	if(File.exists(transform_matrix_file) && lengthOf(tm_var) == 0)
	{			
		bool_overwrite = getBoolean("Transform Matrix already exists, should I overwrite it ?","Overwrite","Skip");
		tm_var = "done";
	}
	else
		bool_overwrite = true;

	if (bool_overwrite)
	{
		// Loop to get the transformation alignment
		current_ID = image_sequence_based_on_regex(ref_channel, current_s, input_file);
		run("Stack to Hyperstack...", "order=xyczt(default) channels=1 slices=&slice_total_number frames=&tp_total_number display=Grayscale");
		getPixelSize(pixel_unit, pixel_width_value, pixel_height_value);
		selectImage(current_ID);
		// waitForUser(current_ID);
		Stack.setFrame(1);



		// ref_channel_idx = find_channel_in_array(ref_channel, channel_array);
		run("Duplicate...", "duplicate slices=&mid_slice");
		mid_slice_file = getImageID();
		selectImage(mid_slice_file);
		image_title    = getTitle();

		print("\\Update"+j+2+":Working on channel " + ref_channel + " using slice " + mid_slice + " to do registration...");
		run("MultiStackReg", "stack_1=&image_title action_1=Align file_1=[&transform_matrix_file] stack_2=None action_2=Ignore file_2=[] transformation=[Rigid Body] save");


		print("\\Update"+j+2+":Working on channel " + ref_channel + ": Registration DONE...");
		run("Close All");
	}

	// 2ND STEP
	// LOOP AND APPLY THE TRANSFORMATION MATRIX TO ALL SLICES

	// Loop through the different channels
	for(i = 0; i < channel_array_length; i++)
	{
		current_channel = channel_array[i];
		
		print("\\Update"+j+2+":Working on channel " + current_channel + " (" + i+1 + "/" + channel_array_length + ")...");
		
		current_ID      = image_sequence_based_on_regex(current_channel, current_s, input_file);

		run("Stack to Hyperstack...", "order=xyczt(default) channels=1 slices=&slice_total_number frames=&tp_total_number display=Grayscale");
		current_ID = getImageID;
		// exit();
		
		// rename(current_channel);
		
		new_name     = old_name + "_" + current_channel + "_" + current_s + "_Aligned";
		rename(new_name);
		aligned_name = "AlignedStack_" + current_channel;

		// Loop through all the slices one by one for registration
		for(k = 1; k <= slice_total_number; k++)
		{
			print("\\Update"+j+2+":Working on channel " + current_channel + " (" + i+1 + "/" + channel_array_length + "): Aligning slice " + k +"/" + slice_total_number +"...");
			selectImage(current_ID);
			run("Duplicate...", "duplicate slices=" + k);
			current_slice_ID = getImageID();
			current_slice_title = getTitle();
			Stack.setFrame(1);
			run("MultiStackReg", "stack_1=&current_slice_title action_1=[Load Transformation File] file_1=[&transform_matrix_file] stack_2=None action_2=Ignore file_2=[] transformation=[Rigid Body]");

			if (k == 1)
				rename(aligned_name);
			else
			{
				run("Concatenate...", "image1=&aligned_name image2=&current_slice_title image3=[-- None --]");
				rename(aligned_name);
			}
		}
		run("Stack to Hyperstack...", "order=xyctz channels=1 slices=&slice_total_number frames=&tp_total_number display=Composite");
		run("Properties...", "channels=1 slices=&slice_total_number frames=&tp_total_number unit=&pixel_unit pixel_width=&pixel_width_value pixel_height=&pixel_height_value voxel_depth=&z_resolution");
		
		out_path = output_folder + new_name + ".ids";
		print("\\Update"+j+2+":Working on channel " + current_channel + " (" + i+1 + "/" + channel_array_length + "): Saving...");

		if(!File.exists(out_path))			
			run("Bio-Formats Exporter", "save=["+ out_path + "] export compression=Uncompressed");
		else
		{
			bool_overwrite = getBoolean("File " + new_name +" already exists, should I overwrite it ?","Overwrite","Skip");
			if (bool_overwrite)
				run("Bio-Formats Exporter", "save=["+ out_path + "] export compression=Uncompressed");
		}
		// close();

		merge_string    = merge_string + "c" + i+1 + "=" + aligned_name + " ";

		delete_temp_files();
	}

	print("\\Update"+j+1+":s " + current_s + ": Saving composite");
	// print(merge_string);
	run("Merge Channels...", merge_string + " create");
	output_composite_folder = output_folder + "Composite" + File.separator;
	new_name_composite      = old_name + "_" + current_s + "_composite";
	out_path_composite      = output_composite_folder + new_name_composite + ".ids";
	run("Properties...", "channels=&channel_array_length slices=&slice_total_number frames=&tp_total_number unit=&pixel_unit pixel_width=&pixel_width_value pixel_height=&pixel_height_value voxel_depth=&z_resolution");
	File.makeDirectory(output_composite_folder);
	run("Bio-Formats Exporter", "save=["+ out_path_composite + "] export compression=Uncompressed");
	print("\\Update"+j+1+":s " + current_s + ": DONE");

	run("Close All");
}

// setBatchMode("exit & display");


print("************************************");
print("Macro finished, images were saved in folder " + output_dir);
print("************************************");