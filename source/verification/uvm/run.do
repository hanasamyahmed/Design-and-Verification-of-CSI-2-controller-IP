vlib work
vlog -f csi_src_files.list +cover=sbeft -covercells
vsim -voptargs=+acc work.csi_tb_top -cover
add wave -position insertpoint sim:/csi_tb_top/tx_if/*
add wave -position insertpoint sim:/csi_tb_top/rx_if/*
run -all
coverage save CSI_coverage.ucdb -onexit -du csi_tb_top
coverage report -detail -cvg -directive -comments -output funcov_assercov_CSI.txt
quit -sim
vcover report CSI_coverage.ucdb -details -annotate -all -output codecov_CSI.txt
vcover report CSI_coverage.ucdb -du=csi_tb_top -recursive -assert -directive -cvg -codeAll -output cov_rprt_summary_CSI.txt
