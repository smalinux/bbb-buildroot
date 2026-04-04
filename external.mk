# Auto-include all package .mk files in the external tree.
# Adding a new package under package/<name>/ is automatically picked up —
# no need to edit this file.
include $(sort $(wildcard $(BR2_EXTERNAL_BBB_PATH)/package/*/*.mk))

# Auto-include all out-of-tree kernel module .mk files.
# Adding a new module under kmodules/<name>/ is automatically picked up.
include $(sort $(wildcard $(BR2_EXTERNAL_BBB_PATH)/kmodules/*/*.mk))
