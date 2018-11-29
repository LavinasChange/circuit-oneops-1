size         = $ciAttr['size']
fs_type      = $ciAttr['fstype']
options      = $ciAttr['options']
logical_name = $node['workorder']['rfcCi']['ciName']
if options.respond_to?('split')
  options_hash = Hash[options.split(',').select{|i| (i != 'defaults')}.map {|i| [i.split('=')[0].to_sym, i.split('=')[1] ? i.split('=')[1] : true]}]
else
  options_hash = ''
end

mount_hash = {}
mount_hash[:type] = fs_type
mount_hash[:device] = $ciAttr['device'] unless $ciAttr['device'].nil? || $ciAttr['device'].empty?
mount_hash[:options] = options_hash unless options_hash.empty?

describe file($mount_point) do
  it { should be_mounted.with( mount_hash) }
end

#Assert volume size
if fs_type != 'tmpfs'
  lvm_dev_id = `mount | grep #{$mount_point}| awk '{print $1}'`.chop
  size_vm = `lvs --noheadings --units g #{lvm_dev_id} | awk '{print $4}'`.chop.to_f.round(0).to_i
else
  size_vm = `df -BG | grep #{$mount_point}| awk '{print $2}'`.chop.to_f.round(0).to_i
end

vg_name = execute_command("lvs | grep #{logical_name}").stdout.split(' ')[1]
vg = `vgdisplay -c #{vg_name}`
vg_size = ((vg.split(':')[11].to_f)/1024/1024).round(0).to_i
vg_lvcount = vg.split(':')[5].to_i

size_wo_g = nil
if size =~ /^\d+G$/           #size specified in Gb - 100G
  size_wo_g = size.to_i
elsif size =~ /^\d+T$/        #size specified in Tb - 1T
  size_wo_g = size.to_i * 1024
elsif size =~ /^\d+\%VG$/     #size specified in % of VG - 70%VG
  size_wo_g = (vg_size.to_f * size.gsub('%VG','').to_i / 100).round(0).to_i
elsif size =~ /^\d+\%FREE$/ && vg_lvcount == 1  #size specified in % of free space in VG - 70%FREE - can only calculate with 1 volume component
  size_wo_g = (vg_size.to_f * size.gsub('%FREE','').to_i / 100).round(0).to_i
else
  puts "Cannot calculate absolute size"
end

describe "size of #{$mount_point}" do
  it "matches requested" do
    expect(size_wo_g).to eql(size_vm)
  end
end unless size_wo_g.nil?

#Assert raid level and status
raid_level = $ciAttr['mode']
raid_name = "/dev/md/#{logical_name}"

describe "RAID array #{raid_name}" do
  let (:raid_status) {execute_command("mdadm --detail #{get_raid_device(raid_name)} | grep 'Raid Level'")}
  let (:out) {raid_status.stdout.split(':')[1]}
  it "RAID status is healthy" do
    expect(raid_status.exitstatus).to eql(0)
  end

  it "RAID level matches requested" do
    expect(out).not_to be_nil
    expect(out.chomp.strip).to eql(raid_level)
  end
end if raid_level != 'no-raid'

#Should create striped LV if multiple slices are available
if $storage && $storage['ciAttributes']['slice_count'].to_i > 1 &&
   raid_level == 'no-raid'

  describe "Logical volume #{logical_name}" do
    let (:cmd) { "lvs --noheadings --segments #{lvm_dev_id} | awk '{print $5}'" }
    let (:lvtype) { execute_command(cmd).stdout.chomp }
    it "is striped" do
      expect(lvtype).to eql('striped')
    end
  end
end

# packages
pkgs = %w(parted lvm2)
pkgs.push('mdadm') if raid_level != 'no-raid'
pkgs.push('xfsprogs') if fs_type == 'xfs'

pkgs.each do |pkg|
  describe package(pkg) do
    it { should be_installed }
  end
end
