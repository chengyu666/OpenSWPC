# Use python to submit jobs automatically.
import os
import re
import subprocess
import sys
import time


def submit_and_get_proc(job_cmd):
    # Create log directory if not exists
    log_dir = "joblog"
    os.makedirs(log_dir, exist_ok=True)
    # Generate log file name with timestamp
    log_name = time.strftime("%Y%m%d_%H%M%S") + ".log"
    log_path = os.path.join(log_dir, log_name)
    print(f"run cmd: {job_cmd}")
    print(f"Log file: {log_path}")
    # Open log file for writing
    log_file = open(log_path, "w")
    # Redirect stdout and stderr to log file
    proc = subprocess.Popen(job_cmd, shell=True,
                            stdout=log_file, stderr=log_file)
    job_id = str(proc.pid)
    print(f"Submitted job: {job_id} @",
          time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()))
    return proc


def modify_source_file(file_path, data_dict):
    """
    Modify the 'xymwdc' format source params in the given file.

    :param file_path: The path to the file to be modified.
    :param data_dict: A dictionary containing the new values for x, y, z, tbeg, trise, mag, strike, dip, and rake.
    """
    # print(f"Modifying source params to: {data_dict}")
    with open(file_path, 'r') as file:
        lines = file.readlines()

    modified_lines = []
    for line in lines:
        if line.strip().startswith("#") or line.strip() == "":
            # Skip comment lines or blank lines
            modified_lines.append(line)
        else:
            # Split the line into columns based on spaces
            columns = line.split()

            # Check if the line has the correct number of columns for 'xymwdc' format
            if len(columns) == 9:  # x, y, z, tbeg, trise, mag, strike, dip, rake
                # Replace the values in the line with the corresponding values from data_dict
                new_line = f"{data_dict['x']:6.1f} {data_dict['y']:5.1f} {data_dict['z']:5.1f} " \
                           f"{data_dict['tbeg']:5.2f} {data_dict['trise']:6.3f} {data_dict['mag']:6.1f} " \
                           f"{data_dict['strike']:8.1f} {data_dict['dip']:6.1f} {data_dict['rake']:6.1f}\n"
                modified_lines.append(new_line)
                print(f"Modified source from:{line} to: {new_line.strip()}")
            else:
                # Otherwise, just keep the original line
                modified_lines.append(line)

    # Write the modified lines back to the file
    with open(file_path, 'w') as file:
        file.writelines(modified_lines)


if __name__ == "__main__":
    source_path = './source_fcy.dat'
    joblist_path = './joblist_chengyu_250529.dat'
    input_path = 'input_fcy.inf'
    result_path = './out/wav'
    num_processor = 36
    start_index = 0
    print(f"Start from job {start_index}.")
    sys.stdout.flush()
    # Read the job file, execute each job, and record the last completed job to autosubmit_log.txt
    with open(joblist_path, 'r') as file:
        lines = file.readlines()
    for index, line in enumerate(lines):
        if index < start_index:
            print(f"Skip job {index}.")
            continue
        print(f"[job {index}].")
        sys.stdout.flush()
        params = line.strip().split()
        # Modify the source file
        data_dict = {
            'x': float(params[0]),
            'y': float(params[1]),
            'z': float(params[2]),
            'tbeg': 0.1,
            'trise': 0.11,
            'mag': 1.0,
            'strike': float(params[3]),
            'dip': float(params[4]),
            'rake': float(params[5])
        }
        modify_source_file(source_path, data_dict)
        command = f"mpirun --bind-to hwthread --map-by hwthread -n {num_processor} --host localhost:40 ../bin/swpc_3d.x -i input_fcy.inf"
        # Submit the job
        proc = submit_and_get_proc(command)
        print(f"Job {proc.pid} is running")
        # Poll the job status
        while proc.poll() is None:
            print('.',end='')
            sys.stdout.flush()
            time.sleep(30)
            
        print(f"Job {proc.pid} completed.")
        os.rename(result_path, f'{result_path}_{index}')
        print(f"Rename {result_path} to {result_path}_{index}")
