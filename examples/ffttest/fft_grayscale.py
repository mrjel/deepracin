import deepracin as dr
from scipy import misc
import numpy as np
from skimage import io

preferred_platform_name = 'Mesa'

with dr.Environment(preferred_platform_name) as env:
    # Properties
    # If true, all debug outputs are printed (Default: False)
    env.debuginfo = True

    # If true, the overall CPU runtimes are profiled and printed (Default: False)
    env.profileCPU = True

    # If true, the GPU kernel runtimes are profiled and printed (Default: False)
    env.profileGPU = True

    # If true, all outputs are supressed (Default: True)
    env.silent = False

    # If not set, a temporary folder will be created in location depending on system
    # Folder is used to store kernels, ptx, and (if model is exported) the exported model)
    env.model_path = 'model/'

# Create empty graph
graph = env.create_graph(interface_layout='HWC')

# Fill graph
# Feed node - Will be fed with data for ea<ch graph application
#feed_node = dr.feed_node(graph, shape=(497, 303, 1))

#feed_node = dr.feed_node(graph, shape=(256, 256, 1))
feed_node = dr.feed_node(graph, shape=(64, 64, 1))

image_paths = ['dia64.png']
#image_paths = ['tigerbw64.png']

# create FFT node
ffttest = dr.FFT(feed_node)
fftshifted = dr.FFTShift(ffttest)

# Mark output nodes (determines what dr.apply() returns)
dr.mark_as_output(fftshifted)

# Print graph to console
dr.print_graph(graph)

# Save deepracin graph
dr.save_graph(graph,env.model_path)

dr.prepare(graph)

for path in image_paths:

    # Feed Input
    img = io.imread(path)
    io.imshow(img)
    io.show()

    #print "Input image dimensions: " + '\n' + str(img.shape) + '\n'
    exp = np.expand_dims(img,2)
    #print "Expanded input image dimensions: " + '\n' + str(exp.shape) + '\n'
    data = np.array(exp).astype(np.float32)
    #print "np.array image dimensions: " + '\n' + str(data.shape) + '\n'
    dr.feed_data(feed_node,data)

    # Apply graph - returns one numpy array for each node marked as output
    fftout = dr.apply(graph)
    #print "fftout image dimensions: " + '\n' + str(fftout.shape) + '\n'

    dat = np.array(fftout[0]).astype(np.float32)
    #print '\n' + "Output image dimensions: " + '\n' + str(dat.shape) + '\n'

    # real part of drfft
    io.imshow(dat[:, :, 0])
    io.show()

    #real part of npfft, axes=[1] means just rows fft
    #io.imshow(np.fft.fft2(img,axes=[1]).real)
    npreal = np.fft.fft2(img).real
    io.imshow(np.fft.fftshift(npreal))
    io.show()

    # imag part of drfft
    io.imshow(dat[:, :, 1])
    io.show()

    #imag part of npfft
    #io.imshow(np.fft.fft2(img,axes=[1]).imag)
    npimag = np.fft.fft2(img).imag
    io.imshow(np.fft.fftshift(npimag))
    io.show()
